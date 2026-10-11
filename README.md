# AI Compare for Apple Silicon

A native macOS application that sends one prompt to selected ChatGPT, Gemini, and Claude browser sessions and displays their replies in three comparison panels. Uses your normal Chrome logins and subscriptions; no API keys, extra service, or app-owned credential store.

## Download

A compiled Apple Silicon app and DMG are produced by the GitHub Actions build. Download the AICompare-AppleSilicon artifact from a successful run. Open the DMG and drag AI Compare to Applications. The app is locally signed but not Apple-notarized; macOS may require Open Anyway in Privacy & Security on first launch. Google Chrome is required.

## Build from source

Requires an Apple Silicon Mac, macOS 13 or later, Google Chrome, and Apple Command Line Tools. This package contains source and a local installer, not a precompiled or notarized app.

1. Unzip this folder on your Mac.
2. Double-click `Install.command`. If macOS prevents opening the downloaded script, open Terminal, type `bash `, drag `Install.command` into Terminal, and press Return. Review the source before running.
3. If prompted to install Command Line Tools, finish their installation and run the installer again.
4. The installer compiles ARM64 code, signs it locally, installs `AI Compare.app` in your user Applications folder, and opens it.
5. Select providers, then click **Open / reconnect sessions**. Sign in directly in Chrome.
6. In Chrome, turn on **View → Developer → Allow JavaScript from Apple Events**. Approve the app's request to control Chrome. If necessary, check macOS System Settings → Privacy & Security → Automation.
7. Write your prompt in AI Compare and click **Send to selected AIs** or press Command-Return.

Chrome remains visible and handles all login, model selection, attachments, and chat history. The app finds an existing tab for each service or creates one. If multiple tabs exist for a provider, it uses the first matching tab; keep one active comparison tab per service. Tabs stay logged in according to each provider's session rules. Sessions can expire and require sign-in again.

## Behavior

- ChatGPT and Gemini are selected initially; Claude is optional.
- Requests are dispatched to each selected service in quick succession. Their generation runs concurrently. Dispatch is not an atomic operation; a service can succeed while another fails.
- Live replies are refreshed every two seconds, and monitoring ends when the response is stable for several checks or after three minutes. Check Chrome for the final authoritative response, especially for long reasoning tasks.
- **Stop monitoring** lets you send again. It does not cancel generation in Chrome; stop that in the service first.
- Existing browser drafts are protected. Clear a draft in Chrome before sending from the app.
- If the send button cannot be found, the filled prompt remains in Chrome for you to send manually. Do not resend blindly: check Chrome to avoid duplicate submissions.
- **Export comparison** writes the last submitted prompt and visible replies to a local text file.
- Pick the model and start a fresh chat in each service's Chrome tab when needed, then reconnect. Existing conversations retain their individual context; identical prompts do not make those contexts identical.

## Privacy

The app communicates only with local Chrome through Apple Events. Chrome sends prompts to the selected providers through their normal websites. There is no analytics, backend, password collection, cookie copying, or additional prompt storage. Exporting creates an unencrypted text file you choose. Chrome Automation permission allows broad browser access; enable it only for software you trust. Adapters verify the exact provider host before inspecting or modifying a page and never script sign-in pages.

## Validation and limitations

JavaScript adapter tests run in a simulated DOM with Node (`node Tests/adapters.test.cjs`). These test routing, draft protection, editor input, reading, and disabled send buttons. This source was produced on Linux: the macOS compile, Apple Events permission flow, real provider DOMs, sign-in, and end-to-end response rendering have NOT been verified on a Mac. Do not treat this package as a tested production release.

Provider HTML is not a supported API and may change, vary by account, or differ with language. The app fails visibly when its known controls are unavailable. Update `Sources/adapter.js` and `Sources/send.js` selectors and rerun the installer if needed. The adapters currently target English send-button labels. Responses are plain text, without images, rich Markdown, citations as clickable links, file uploads, or automatic model selection. Subscription limits and availability still apply.

If macOS reports a compiler error, copy the complete output for troubleshooting. Uninstall by deleting the app; this does not remove your Chrome sessions or chats.
