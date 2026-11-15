# DEX//PROMPTENDER — Keyboard Focus / Cannot Type Repair

Source baseline: `6c1c195f40615ff8c653b0b48d98976e4ac9b4ca`.
Target: native macOS menu-bar `LSUIElement` app, SwiftUI + AppKit, installed on an Apple Silicon MacBook Air.

## User-reported blocker

Buttons and appearance sliders worked, but normal typing did not work in any input fields. This is a critical failure of the product's main purpose. Previous UI QA tested rendered appearance and control state but omitted real keyboard focus and typing.

## Source diagnosis

- `AppDelegate.togglePopover` and the return-from-detached-window branch called `NSWindow.becomeKey()` directly. Apple documents this as an AppKit notification callback and explicitly prohibits calling it directly. The request API is `makeKey()` (or `makeKeyAndOrderFront` for panels).
- The app uses `LSUIElement=true`, so opening a status item does not necessarily make the application active. Key-window changes depend on application activation, which may arrive after the popover is shown.
- Detached Mixing Room and Local Chat windows previously ordered themselves key before asking the application to activate.
- The raw prompt's `NSViewRepresentable` was attached to an unused SwiftUI `@FocusState`, despite using a native `NSTextView` embedded in `NSScrollView`.

## Bounded correction

- `PromptenderWindowFocus.activateAndFocus`: request app activation and `NSWindow.makeKey()` rather than sending the `becomeKey` callback.
- `PromptenderWindowFocus.activateAndShow`: activate before `makeKeyAndOrderFront` for detached Mixing Room and Local Chat panels.
- Route all status-button popover presentations through one helper, then re-request key focus after the hosting window finishes attaching if needed.
- `applicationDidBecomeActive` reasserts key status for an already-shown popover after asynchronous activation.
- Explicit `becomesKeyOnlyIfNeeded=false` for editor panels.
- Remove unused SwiftUI `@FocusState` from the raw `TransparentTextEditor`; explicitly set `NSTextView.isEditable=true` and `isSelectable=true`.
- Preserve menu-bar-only identity, the existing UI, compile workflow, user settings, the installed app, secrets, and DexDiffusion. No user data or network-backed state was changed in testing.

## Test results and evidence boundaries

- `swift test` **47/47 tests across 10 suites passed** (including existing appearance, compiler, wildcard, and Serve regression tests).
- The new `NativeKeyboardInputRegressionTests` forbid future direct calls to `becomeKey()`, and prove the focus helper requests the correct key API and that a native panel routes synthetic `keyDown` events into a real `NSTextField` and `NSTextView`.
- `HostedNativeKeyboardControlsTests` create a real `NSHostingView` containing SwiftUI `TextField`, `SecureField`, `TextEditor` and the project's `TransparentTextEditor`; synthetic `keyDown` changes the actual backing AppKit controls and all four SwiftUI bindings.
- A separate ephemeral menu-bar `.app` was launched on Big Mac for a focused NSPopover integration probe. It confirmed the popup window could become key and synthetic `keyDown` reached the popup field. Remote SSH could not make the GUI app frontmost; `isKeyWindow` was false. This does NOT prove attended MacBook keyboard focus.
- Big Mac `System Events` desktop automation was blocked by macOS permissions (-1743). No permission bypass was attempted.
- **Release gate still open:** After installing the verified new `.app` on the MacBook, physically click the menu-bar popover and type into Raw Input. Confirm text appears and is editable. Repeat after foregrounding another app and reopening the popover. Then test the detached Mixing Room and a normal Settings field. If any fails, treat the defect as NOT CLOSED.

## Final packaging and publication

- Big Mac release build: PASS (arm64 Mach-O). Bundle identifier: com.andrew.dexpromptender. Plist lint: PASS. Strict ad-hoc codesign: PASS. App launched and quit cleanly in Big Mac GUI session.
- Exact executable SHA-256: 573d1aaa6452025f0f6dc69b77102b4307c880427a3ffebbcef787ab467ae251.
- Big Mac packaged app: /Users/bigmac/Projects/DEX_Promp-tender/dist/DexPromptender.app.
- Git publication and MacBook installation require separately confirmed readbacks. Never describe the source-only regression test as proof of attended MacBook typing.
