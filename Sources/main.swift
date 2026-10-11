import Cocoa

struct Provider {
    let id: String
    let name: String
    let url: String
}
let providers = [Provider(id: "chatgpt", name: "ChatGPT", url: "https://chatgpt.com/"), Provider(id: "gemini", name: "Gemini", url: "https://gemini.google.com/app"), Provider(id: "claude", name: "Claude", url: "https://claude.ai/new")]
func literal(_ s: String) -> String { String(data: try! JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed]), encoding: .utf8)! }
func appleLiteral(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\"" }

final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var prompt = NSTextView()
    var outputs: [NSTextView] = []
    var toggles: [NSButton] = []
    var labels: [NSTextField] = []
    var sendButton: NSButton!
    var tabIDs: [String: Int] = [:]
    var pending = Set<Int>()
    var baselines: [Int: String] = [:]
    var baselineCounts: [Int: Int] = [:]
    var deadlines: [Int: Date] = [:]
    var timer: Timer?
    var dispatching = false
    var polling = false
    var generation = 0
    var lastPrompt = ""
    var lastTexts: [Int: String] = [:]
    var stableCounts: [Int: Int] = [:]
    let worker = DispatchQueue(label: "AICompare.browser")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit AI Compare", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); root.submenu = appMenu
        let editRoot = NSMenuItem(); menu.addItem(editRoot); let edit = NSMenu(title: "Edit"); editRoot.submenu = edit
        for (name, action, key) in [("Copy", "copy:", "c"),("Paste", "paste:", "v"),("Cut", "cut:", "x"),("Select All", "selectAll:", "a"),("Undo", "undo:", "z")] { edit.addItem(withTitle:name, action:Selector(action), keyEquivalent:key) }
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1180,height:780), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = "AI Compare"; window.minSize = NSSize(width:850,height:620)
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12; stack.edgeInsets = NSEdgeInsets(top:18,left:18,bottom:18,right:18)
        window.contentView = stack
        let title = NSTextField(labelWithString:"One prompt. Multiple perspectives."); title.font = .boldSystemFont(ofSize:24); stack.addArrangedSubview(title)
        let note = NSTextField(wrappingLabelWithString:"1. Open sessions and sign in using Chrome.  2. In Chrome: View → Developer → Allow JavaScript from Apple Events.  3. Send a shared prompt. Logins stay in your Chrome profile.")
        stack.addArrangedSubview(note)
        let tools = NSStackView(); tools.orientation = .horizontal
        tools.addArrangedSubview(NSButton(title:"Open / reconnect sessions", target:self, action:#selector(openSessions)))
        tools.addArrangedSubview(NSButton(title:"Stop monitoring", target:self, action:#selector(stopMonitoring)))
        tools.addArrangedSubview(NSButton(title:"Export comparison…", target:self, action:#selector(exportComparison)))
        stack.addArrangedSubview(tools)
        let columns = NSStackView(); columns.orientation = .horizontal; columns.distribution = .fillEqually; columns.spacing = 12
        for (i,p) in providers.enumerated() {
            let column = NSStackView(); column.orientation = .vertical; column.spacing = 8
            let toggle = NSButton(checkboxWithTitle:p.name,target:nil,action:nil); toggle.state = i < 2 ? .on : .off; toggles.append(toggle); column.addArrangedSubview(toggle)
            let status = NSTextField(labelWithString:"Ready to connect"); status.lineBreakMode = .byTruncatingTail; status.toolTip = "Session status"; labels.append(status); column.addArrangedSubview(status)
            let view = NSTextView(); view.isEditable = false; view.isRichText = false; view.font = .systemFont(ofSize:14); view.textContainerInset = NSSize(width:12,height:12); outputs.append(view)
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = view; scroll.borderType = .bezelBorder; configureTextView(view, in: scroll); column.addArrangedSubview(scroll)
            scroll.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true
            columns.addArrangedSubview(column)
        }
        stack.addArrangedSubview(columns)
        columns.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive = true
        columns.heightAnchor.constraint(greaterThanOrEqualToConstant:280).isActive = true
        prompt.font = .systemFont(ofSize:15); prompt.isRichText = false; prompt.allowsUndo = true; prompt.textContainerInset = NSSize(width:10,height:10)
        let input = NSScrollView(); input.hasVerticalScroller = true; input.borderType = .bezelBorder; input.documentView = prompt; configureTextView(prompt, in: input)
        stack.addArrangedSubview(input); input.heightAnchor.constraint(equalToConstant:110).isActive = true; input.widthAnchor.constraint(equalTo:columns.widthAnchor).isActive = true
        sendButton = NSButton(title:"Send to selected AIs",target:self,action:#selector(send)); sendButton.keyEquivalent = "\r"; sendButton.keyEquivalentModifierMask = [.command]; stack.addArrangedSubview(sendButton)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard self.window.isVisible, self.outputs.count == 3, self.sendButton != nil else { exit(1) }
                print("AI Compare launch smoke test passed")
                NSApp.terminate(nil)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.poll() }
    }
    func configureTextView(_ view: NSTextView, in scroll: NSScrollView) {
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func script(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source:source) else { throw NSError(domain:"Script",code:1,userInfo:[NSLocalizedDescriptionKey:"Invalid browser script"]) }
        let result = script.executeAndReturnError(&error)
        if let error = error { throw NSError(domain:"Chrome",code:1,userInfo:[NSLocalizedDescriptionKey:error[NSAppleScript.errorMessage] as? String ?? "Allow Chrome Automation in System Settings → Privacy & Security → Automation."]) }
        return result.stringValue ?? ""
    }
    func connect(_ p: Provider) throws -> Int {
        let result = try script("""
        tell application "Google Chrome"
            if (count of windows) is 0 then make new window
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t starts with \(appleLiteral(p.url.components(separatedBy:"/").prefix(3).joined(separator:"/") + "/")) then return (id of t) as text
                end repeat
            end repeat
            tell front window
                set t to make new tab with properties {URL:\(appleLiteral(p.url))}
                return (id of t) as text
            end tell
        end tell
        """)
        guard let id = Int(result) else { throw NSError(domain:"Chrome",code:2,userInfo:[NSLocalizedDescriptionKey:"Cannot identify browser tab"]) }; return id
    }
    func evaluate(_ id: Int, _ js: String) throws -> [String: Any] {
        let result = try script("""
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if id of t is \(id) then return execute t javascript \(appleLiteral(js))
                end repeat
            end repeat
            error "Session tab closed. Click Open / reconnect sessions."
        end tell
        """)
        guard let data = result.data(using:.utf8), let object = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw NSError(domain:"Adapter",code:3,userInfo:[NSLocalizedDescriptionKey:"Unexpected browser response"]) }
        if let error = object["error"] as? String { throw NSError(domain:"Adapter",code:4,userInfo:[NSLocalizedDescriptionKey:error]) }; return object
    }
    func adapter(_ p: Provider, _ action: String, _ text: String = "", file: String = "adapter") throws -> String {
        guard let url = Bundle.main.url(forResource:file,withExtension:"js") else { throw NSError(domain:"Resources",code:1,userInfo:[NSLocalizedDescriptionKey:"Missing browser adapter"]) }
        return try String(contentsOf:url,encoding:.utf8).replacingOccurrences(of:"__PROVIDER__",with:literal(p.id)).replacingOccurrences(of:"__ACTION__",with:literal(action)).replacingOccurrences(of:"__PROMPT__",with:literal(text))
    }
    @objc func openSessions() {
        let selected = providers.indices.filter { toggles[$0].state == .on }
        worker.async { for i in selected { do { let id = try self.connect(providers[i]); DispatchQueue.main.async { self.tabIDs[providers[i].id] = id; self.labels[i].stringValue = "Connected — sign in in Chrome" } } catch { DispatchQueue.main.async { self.labels[i].stringValue = error.localizedDescription } } } }
    }
    @objc func send() {
        let text = prompt.string.trimmingCharacters(in:.whitespacesAndNewlines)
        let selected = providers.indices.filter { toggles[$0].state == .on }
        guard !text.isEmpty, !selected.isEmpty, pending.isEmpty, !dispatching else { return }
        dispatching = true
        for i in providers.indices { outputs[i].string = selected.contains(i) ? "Preparing…" : "Not included in this comparison" }
        sendButton.isEnabled = false
        generation += 1
        lastPrompt = text
        let epoch = generation
        let knownTabs = tabIDs
        worker.async {
            for i in selected {
                do {
                    guard let id = knownTabs[providers[i].id] else { throw NSError(domain:"Session",code:1,userInfo:[NSLocalizedDescriptionKey:"Click Open / reconnect sessions first."]) }
                    let prepared = try self.evaluate(id, self.adapter(providers[i],"prepare",text))
                    Thread.sleep(forTimeInterval:0.4)
                    _ = try self.evaluate(id,self.adapter(providers[i],"send",file:"send"))
                    let before = prepared["before"] as? [String:Any] ?? [:]
                    DispatchQueue.main.async {
                        guard self.generation == epoch else { return }
                        self.lastTexts[i] = ""; self.stableCounts[i] = 0
                        self.baselines[i] = before["text"] as? String ?? ""; self.baselineCounts[i] = before["count"] as? Int ?? 0
                        self.pending.insert(i); self.deadlines[i] = Date().addingTimeInterval(180)
                        self.outputs[i].string = "Waiting for response…"; self.labels[i].stringValue = "Sent — monitoring"
                    }
                } catch { DispatchQueue.main.async { guard self.generation == epoch else { return }; self.labels[i].stringValue = "Needs attention"; self.outputs[i].string = error.localizedDescription } }
            }
            DispatchQueue.main.async { self.dispatching = false; self.sendButton.isEnabled = self.pending.isEmpty }
        }
    }
    func poll() {
        guard !polling, !pending.isEmpty else { return }; polling = true
        let current = pending; let ids = tabIDs; let epoch = generation
        worker.async {
            for i in current {
                do {
                    guard let id = ids[providers[i].id] else { continue }
                    let response = try self.evaluate(id,self.adapter(providers[i],"read"))
                    DispatchQueue.main.async {
                        guard self.generation == epoch, self.pending.contains(i) else { return }
                        let text = response["text"] as? String ?? ""
                        let count = response["count"] as? Int ?? 0
                        if !text.isEmpty && (count > (self.baselineCounts[i] ?? 0) || text != self.baselines[i]) { self.outputs[i].string = text; self.labels[i].stringValue = "Response received — monitoring"
                            if text == self.lastTexts[i] { self.stableCounts[i, default: 0] += 1 } else { self.stableCounts[i] = 0 }
                            self.lastTexts[i] = text
                            if self.stableCounts[i, default: 0] >= 5 { self.pending.remove(i); self.labels[i].stringValue = "Response stable — verify completion in Chrome" }
                        }
                        if Date() > (self.deadlines[i] ?? Date()) { self.pending.remove(i); self.labels[i].stringValue = "Monitoring ended — check Chrome for completion" }
                    }
                } catch { DispatchQueue.main.async { if self.generation == epoch { self.pending.remove(i); self.labels[i].stringValue = error.localizedDescription } } }
            }
            DispatchQueue.main.async { self.polling = false; self.sendButton.isEnabled = self.pending.isEmpty && !self.dispatching }
        }
    }
    @objc func stopMonitoring() { guard !dispatching else { return }; generation += 1; pending.removeAll(); sendButton.isEnabled = true; for label in labels { label.stringValue = "Monitoring stopped; browser may still be generating" } }
    @objc func exportComparison() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "AI-comparison.txt"
        if panel.runModal() == .OK, let url = panel.url {
            let text = "AI Compare — \(Date())\n\nPROMPT\n\(lastPrompt)\n\n" + providers.indices.map { "\(providers[$0].name)\n\(outputs[$0].string)" }.joined(separator:"\n\n--------------------\n\n")
            do { try text.write(to:url,atomically:true,encoding:.utf8) } catch { let alert = NSAlert(); alert.messageText = "Export failed"; alert.informativeText = error.localizedDescription; alert.runModal() }
        }
    }
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
