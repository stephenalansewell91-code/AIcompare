# AI Compare — in-app sessions

Native Apple Silicon macOS app with ChatGPT and Gemini running directly in embedded WebKit panels. An optional third panel supports Claude. Sign in inside each panel once; the app keeps website storage on your Mac and saves session cookies in macOS Keychain and reopens your last chat URLs. The shared prompt is submitted to the selected panels, where replies stream through each provider's normal interface.

Keychain may ask permission when an updated locally signed build accesses saved sessions. Allow access for AI Compare to restore them.

No Chrome, Apple Events, external browser, API keys, or proxy service is used. Login popups open as additional windows inside AI Compare and share its persistent website store. Model selection, chat history, and file selection are handled by each provider's own UI.

## Install the compiled app

Requires macOS 13+ on Apple Silicon. Download the DMG from the successful GitHub Actions build, open it, and drag AI Compare to Applications. Quit and replace the previous version before launching. This build is locally signed and not Apple-notarized; if macOS blocks it, use Privacy & Security → Open Anyway after attempting to open it.

1. Sign into ChatGPT and Gemini inside the app's panels.
2. Leave the checkboxes enabled for services you want to query.
3. Enter a prompt in the bottom box and click Send, or press Command-Return.
4. Read and interact with each response directly in its panel.

Home returns to the provider's homepage. Reload refreshes its page. Show Claude adds a third embedded session. Signing out on a provider's page signs that provider out of the app. Cookies are shared across the app's embedded windows, which allows Google-based authentication popups to use the same session store.

## Important compatibility boundary

Providers may reject embedded browsers at sign-in or during anti-bot checks. Google OAuth in particular restricts embedded authorization. Persistent storage preserves sessions after successful sign-in; it cannot override a provider's sign-in policy or session expiry. This app does not disguise WebKit, copy browser cookies, or bypass authentication restrictions. If a provider blocks embedded sign-in, that service will not work in this version. Real authenticated ChatGPT/Gemini/Claude sessions have not been verified by the build service.

Website editors and send-button selectors are not stable public APIs. If a layout changes, the shared prompt may fail while direct interaction with the page still works. A failed send shows an error above its panel. Existing drafts are preserved, and a prompt is never automatically submitted twice. Send requests are independent; one provider can succeed while another fails.

## Tests and build

`node Tests/adapters.test.cjs` checks routing, existing drafts, changed drafts, multiline text, busy states, delayed buttons, and exactly-once submission. The macOS workflow builds ARM64, verifies the signature, submits the same prompt through two real WKWebView instances using local HTML fixtures, checks each was submitted once, and relaunches the process to verify a persistent test cookie survived. A fixture-only UI preview is included with build artifacts. Tests do not sign into real accounts.

`bash Build.command` produces an app, DMG, and ZIP on a Mac with Apple Command Line Tools. `Install.command` is an optional local source build installer; it is not required when using the DMG.
