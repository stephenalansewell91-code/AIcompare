import Cocoa
import WebKit
import Security

struct Provider {
    let id: String
    let name: String
    let host: String
    let home: String
}
let providers = [
    Provider(id: "chatgpt", name: "ChatGPT", host: "chatgpt.com", home: "https://chatgpt.com/"),
    Provider(id: "gemini", name: "Gemini", host: "gemini.google.com", home: "https://gemini.google.com/app"),
    Provider(id: "claude", name: "Claude", host: "claude.ai", home: "https://claude.ai/new")
]
func jsonLiteral(_ value: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), encoding: .utf8)!
}
let testing = CommandLine.arguments.contains("--integration-test")
let restoring = CommandLine.arguments.contains("--verify-persistence")

final class SessionVault: NSObject, WKHTTPCookieStoreObserver {
    let cookies = WKWebsiteDataStore.default().httpCookieStore
    let service = "com.aicompare.desktop.cookies" + ((testing || restoring) ? ".test" : "")
    var ready = false
    var pendingSave: DispatchWorkItem?
    var onError: ((String) -> Void)?
    var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "embedded-sessions"] }
    func restore(_ completion: @escaping () -> Void) {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let records = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            if status != errSecItemNotFound && status != errSecSuccess { onError?("Keychain session restore failed (\(status)).") }
            begin(); completion(); return
        }
        let restored = records.compactMap { record -> HTTPCookie? in
            let properties = Dictionary(uniqueKeysWithValues: record.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            guard let cookie = HTTPCookie(properties: properties), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return nil }
            return cookie
        }
        let group = DispatchGroup()
        for cookie in restored { group.enter(); cookies.setCookie(cookie) { group.leave() } }
        group.notify(queue: .main) { self.begin(); completion() }
    }
    func begin() { ready = true; cookies.add(self) }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard ready else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { self.save { _ in } }; pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    func save(_ completion: @escaping (Bool) -> Void) {
        pendingSave?.cancel()
        cookies.getAllCookies { cookies in
            let records: [[String: Any]] = cookies.compactMap { cookie in
                guard let properties = cookie.properties else { return nil }
                return Dictionary(uniqueKeysWithValues: properties.compactMap { key, value in
                    // Cookie properties are plist scalar values on supported macOS versions.
                    if value is String || value is NSNumber || value is Date { return (key.rawValue, value) }
                    return nil
                })
            }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: records, format: .binary, options: 0)
                var status = SecItemUpdate(self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
                if status == errSecItemNotFound {
                    var item = self.query; item[kSecValueData as String] = data
                    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    status = SecItemAdd(item as CFDictionary, nil)
                }
                if status != errSecSuccess { self.onError?("Keychain session save failed (\(status)).") }
                completion(status == errSecSuccess)
            } catch { self.onError?(error.localizedDescription); completion(false) }
        }
    }
}

final class Fixture: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width"><style>
        body{font:16px -apple-system;padding:24px;color:#243244;background:#f6f8fb}h2{font-size:25px}
        textarea{width:90%;height:150px;padding:12px;font:16px -apple-system}button{margin-top:16px;padding:12px}
        </style></head><body><h2>Embedded session test</h2><p>Local fixture — no account or AI service is contacted.</p>
        <textarea id="prompt-textarea" role="textbox"></textarea><br>
        <button data-testid="send-button" aria-label="Send message" class="send-button" onclick="document.getElementById('reply').textContent=document.querySelector('textarea').value; window.sentCount=(window.sentCount||0)+1; document.querySelector('textarea').value=''">Send</button>
        <p id="reply"></p></body></html>
        """
        let data = Data(html.utf8)
        urlSchemeTask.didReceive(URLResponse(url: urlSchemeTask.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

final class Popup: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onClose: (() -> Void)?
    var observation: NSKeyValueObservation?
    init(configuration: WKWebViewConfiguration, delegate: Pane) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false; window.delegate = self
        window.title = "AI Compare — sign in / linked page"
        window.contentView = webView; webView.uiDelegate = delegate; webView.navigationDelegate = delegate
        observation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            self?.window.title = "AI Compare — " + (view.url?.host ?? "Sign in")
        }
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class Pane: NSObject, WKNavigationDelegate, WKUIDelegate {
    let provider: Provider
    let view = NSStackView()
    let webView: WKWebView
    let include: NSButton
    let status = NSTextField(labelWithString: "Loading…")
    let address = NSTextField(labelWithString: "")
    var popups: [Popup] = []
    var didLoad: (() -> Void)?
    private var observation: NSKeyValueObservation?
    init(_ provider: Provider) {
        self.provider = provider
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if testing || restoring { configuration.setURLSchemeHandler(Fixture(), forURLScheme: "aicompare-test") }
        webView = WKWebView(frame: .zero, configuration: configuration)
        include = NSButton(checkboxWithTitle: provider.name, target: nil, action: nil)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        include.state = .on; include.font = .boldSystemFont(ofSize: 15)
        let toolbar = NSStackView(views: [include, NSButton(title: "←", target: self, action: #selector(back)), NSButton(title: "Reload", target: self, action: #selector(reload)), NSButton(title: "Home", target: self, action: #selector(home))])
        toolbar.orientation = .horizontal; toolbar.spacing = 6
        view.addArrangedSubview(toolbar)
        address.font = .systemFont(ofSize: 11); address.textColor = .secondaryLabelColor; address.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: 12); status.lineBreakMode = .byTruncatingTail
        view.addArrangedSubview(address); view.addArrangedSubview(status); view.addArrangedSubview(webView)
        for child in [address, status, webView] as [NSView] { child.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true }
        webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        observation = webView.observe(\.url, options: [.new]) { [weak self] page, _ in
            guard let self = self else { return }
            self.address.stringValue = page.url?.host ?? self.provider.host
            self.address.toolTip = page.url?.absoluteString
            if let url = page.url, url.scheme == "https", url.host == self.provider.host {
                UserDefaults.standard.set(url.absoluteString, forKey: "lastURL." + self.provider.id)
            }
        }
    }
    func start() {
        if testing || restoring { webView.load(URLRequest(url: URL(string: "aicompare-test://\(provider.host)/")!)); return }
        let saved = UserDefaults.standard.string(forKey: "lastURL." + provider.id).flatMap(URL.init(string:))
        let url = saved?.scheme == "https" && saved?.host == provider.host ? saved! : URL(string: provider.home)!
        webView.load(URLRequest(url: url))
    }
    func message(_ text: String, error: Bool = false) {
        status.stringValue = text; status.toolTip = text; status.textColor = error ? .systemRed : .secondaryLabelColor
    }
    @objc func home() { webView.load(URLRequest(url: URL(string: provider.home)!)) }
    @objc func back() { webView.goBack() }
    @objc func reload() { webView.reload() }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === self.webView { message("Loading…") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView { message("Page loaded • sign in here if needed"); didLoad?() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        message(error.localizedDescription, error: true)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { message("Page process stopped. Click Reload.", error: true) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme ?? ""
        let allowed = ["https", "http", "about", "blob"].contains(scheme) || ((testing || restoring) && scheme == "aicompare-test")
        if !allowed { message("This link requires an external application and was not opened.", error: true) }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let popup = Popup(configuration: configuration, delegate: self)
        popups.append(popup)
        popup.onClose = { [weak self, weak popup] in self?.popups.removeAll { $0 === popup } }
        return popup.webView
    }
    func webViewDidClose(_ webView: WKWebView) { popups.first { $0.webView === webView }?.window.close() }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = frame.request.url?.host ?? provider.name; alert.informativeText = message; alert.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = frame.request.url?.host ?? provider.name; alert.informativeText = message; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel"); completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }
    func run(_ action: String, prompt: String, token: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        do {
            let url = Bundle.main.url(forResource: "adapter", withExtension: "js")!
            let source = try String(contentsOf: url, encoding: .utf8)
            // Arguments are passed as values, never interpolated into executable JavaScript.
            webView.callAsyncJavaScript(source, arguments: ["provider": provider.id, "action": action, "prompt": prompt, "token": token], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    if let response = value as? [String: Any] {
                        if let message = response["error"] as? String { completion(.failure(NSError(domain: "AICompare", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))) }
                        else { completion(.success(response)) }
                    } else { completion(.failure(NSError(domain: "AICompare", code: 2, userInfo: [NSLocalizedDescriptionKey: "The page returned an unexpected result."]))) }
                case .failure(let error): completion(.failure(error))
                }
            }
        } catch { completion(.failure(error)) }
    }
    func send(_ text: String, token: String, completion: @escaping (Bool) -> Void) {
        message("Preparing prompt…")
        run("prepare", prompt: text, token: token) { result in
            switch result {
            case .failure(let error): self.message(error.localizedDescription, error: true); completion(false)
            case .success: self.submit(text, token: token, attempts: 12, completion: completion)
            }
        }
    }
    private func submit(_ text: String, token: String, attempts: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.run("send", prompt: text, token: token) { result in
                switch result {
                case .failure(let error): self.message(error.localizedDescription, error: true); completion(false)
                case .success(let response):
                    if response["sent"] as? Bool == true { self.message("Sent • response appears below"); completion(true) }
                    else if attempts > 1 { self.submit(text, token: token, attempts: attempts - 1, completion: completion) }
                    else { self.message("Prompt filled. Send button unavailable; submit it in this panel.", error: true); completion(false) }
                }
            }
        }
    }
}

final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let prompt = NSTextView()
    var panes: [Pane] = []
    let sendButton = NSButton(title: "Send to both AIs", target: nil, action: nil)
    let summary = NSTextField(labelWithString: "Sign in once in each panel. Your sessions are saved on this Mac.")
    let showClaude = NSButton(checkboxWithTitle: "Show Claude", target: nil, action: nil)
    let vault = SessionVault()
    var sending = false
    var loaded = Set<String>()
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AI Compare • In-app sessions"; window.minSize = NSSize(width: 1000, height: 650); window.isReleasedWhenClosed = false
        let root = NSView(); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)])
        let title = NSTextField(labelWithString: "One prompt. Side by side."); title.font = .boldSystemFont(ofSize: 23)
        let header = NSStackView(views: [title, NSView(), showClaude]); header.orientation = .horizontal
        showClaude.target = self; showClaude.action = #selector(toggleClaude)
        showClaude.state = UserDefaults.standard.bool(forKey: "showClaude") ? .on : .off
        stack.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor; stack.addArrangedSubview(summary)
        let columns = NSStackView(); columns.orientation = .horizontal; columns.distribution = .fillEqually; columns.spacing = 12; columns.detachesHiddenViews = true
        for provider in providers {
            let pane = Pane(provider); panes.append(pane); columns.addArrangedSubview(pane.view)
            pane.didLoad = { [weak self] in self?.pageLoaded(provider.id) }
        }
        panes[2].view.isHidden = showClaude.state != .on
        stack.addArrangedSubview(columns); columns.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        let label = NSTextField(labelWithString: "Shared prompt"); label.font = .boldSystemFont(ofSize: 13); stack.addArrangedSubview(label)
        let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        prompt.font = .systemFont(ofSize: 15); prompt.isRichText = false; prompt.allowsUndo = true; prompt.textContainerInset = NSSize(width: 10, height: 10)
        prompt.minSize = .zero; prompt.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        prompt.isVerticallyResizable = true; prompt.isHorizontallyResizable = false; prompt.autoresizingMask = [.width]; prompt.textContainer?.widthTracksTextView = true
        scroll.documentView = prompt; stack.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 94).isActive = true; scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sendButton.target = self; sendButton.action = #selector(send); sendButton.bezelStyle = .rounded; sendButton.keyEquivalent = "\r"; sendButton.keyEquivalentModifierMask = [.command]
        let hint = NSTextField(labelWithString: "⌘ Return to send • Use each panel to choose its model or start a new chat"); hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        let footer = NSStackView(views: [sendButton, hint]); footer.spacing = 12; stack.addArrangedSubview(footer)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        vault.onError = { [weak self] message in self?.summary.stringValue = message }
        vault.restore {
            if restoring { self.verifyPersistedCookie() }
            else { for pane in self.panes.prefix(self.showClaude.state == .on ? 3 : 2) { pane.start() } }
        }
        if testing || restoring { DispatchQueue.main.asyncAfter(deadline: .now() + 25) { print("Integration test timed out"); exit(1) } }
    }
    func setupMenu() {
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About AI Compare", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "Quit AI Compare", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem); let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = menu
    }
    @objc func about() {
        let alert = NSAlert(); alert.messageText = "AI Compare 0.2 — In-app sessions"
        alert.informativeText = "Each service runs inside this app. Cookies and website storage are saved locally. Sign-in popups also stay inside the app. Providers may expire sessions or reject embedded sign-in; this app cannot override those restrictions. No external browser, API keys, or extra AI subscription is used."
        alert.runModal()
    }
    @objc func toggleClaude() {
        let show = showClaude.state == .on; panes[2].view.isHidden = !show; UserDefaults.standard.set(show, forKey: "showClaude")
        if show && panes[2].webView.url == nil { panes[2].start() }
        sendButton.title = show ? "Send to selected AIs" : "Send to selected AIs"
    }
    @objc func send() {
        let text = prompt.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = panes.filter { !$0.view.isHidden && $0.include.state == .on }
        guard !sending else { return }
        guard !text.isEmpty, !selected.isEmpty else { summary.stringValue = "Enter a prompt and select at least one AI."; return }
        sending = true; sendButton.isEnabled = false; showClaude.isEnabled = false
        let token = UUID().uuidString; var remaining = selected.count; var successes = 0
        summary.stringValue = "Sending to \(selected.map { $0.provider.name }.joined(separator: ", "))…"
        for pane in selected {
            pane.send(text, token: token) { success in
                if success { successes += 1 }; remaining -= 1
                if remaining == 0 {
                    self.sending = false; self.sendButton.isEnabled = true; self.showClaude.isEnabled = true
                    self.summary.stringValue = successes == selected.count ? "Sent to all selected AIs. Replies stream directly in each panel." : "Sent to \(successes) of \(selected.count). See the red message above any panel that failed."
                }
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard vault.ready else { return .terminateNow }
        vault.save { success in
            if (testing || restoring) && !success { print("Session save failed"); exit(1) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func pageLoaded(_ id: String) {
        guard testing || restoring else { return }
        loaded.insert(id); guard loaded.count == 2 else { return }
        let text = "A shared prompt\nwith quotes: \"hello\" and unicode ✓"
        prompt.string = text
        var remaining = 2
        for pane in panes.prefix(2) {
            pane.send(text, token: "integration-1") { success in
                guard success else { print("Embedded send failed: \(pane.status.stringValue)"); exit(1) }
                pane.webView.evaluateJavaScript("JSON.stringify({text:document.getElementById('reply').textContent,count:window.sentCount})") { value, error in
                    guard error == nil, let string = value as? String, let data = string.data(using: .utf8), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], result["text"] as? String == text, result["count"] as? Int == 1 else { print("Shared prompt mismatch or duplicate send"); exit(1) }
                    remaining -= 1; if remaining == 0 { self.finishTests() }
                }
            }
        }
    }
    func verifyPersistedCookie() {
        print("Checking saved cookie in a fresh process")
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            guard let cookie = cookies.first(where: { $0.name == "AIComparePersistenceTest" && $0.value == "saved" }) else { print("Persistent cookie missing after restart"); exit(1) }
            print("Persistent cookie survived app restart")
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) { NSApp.terminate(nil) }
        }
    }
    func finishTests() {
        // WebKit renders out of process; use its snapshot API for the panel content.
        guard let root = window.contentView else { exit(1) }
        var captures: [(NSImage, NSRect)] = []
        var left = 2
        for pane in panes.prefix(2) {
            pane.webView.takeSnapshot(with: nil) { image, error in
                guard let image = image, error == nil else { print("WebKit snapshot failed"); exit(1) }
                captures.append((image, pane.webView.convert(pane.webView.bounds, to: root)))
                left -= 1
                if left == 0 {
                    let composite = NSImage(size: root.bounds.size)
                    composite.lockFocus()
                    NSColor.windowBackgroundColor.setFill(); root.bounds.fill()
                    if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                        root.cacheDisplay(in: root.bounds, to: bitmap)
                        bitmap.draw(in: root.bounds)
                    }
                    for (image, rect) in captures { image.draw(in: rect) }
                    composite.unlockFocus()
                    if let tiff = composite.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "dist/InApp-Preview.png"))
                    }
                    self.persistTestCookie()
                }
            }
        }
    }
    func persistTestCookie() {
        let cookie = HTTPCookie(properties: [.domain: "session-test.invalid", .path: "/", .name: "AIComparePersistenceTest", .value: "saved", .secure: "TRUE", .expires: Date().addingTimeInterval(3600)])!
        WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { print("Embedded WebKit shared-prompt integration test passed"); NSApp.terminate(nil) }
        }
    }
}
let app = NSApplication.shared
let delegate = App(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
