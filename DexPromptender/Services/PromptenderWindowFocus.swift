import AppKit

/// A menu-bar-only app must explicitly request a key window before text
/// controls can receive keyboard events. NSWindow.becomeKey() is a callback
/// invoked BY AppKit; it is not a request to focus the window.
@MainActor
enum PromptenderWindowFocus {
    @discardableResult
    static func activateAndFocus(_ window: NSWindow?) -> Bool {
        guard let window, window.canBecomeKey else { return false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        return window.isKeyWindow
    }

    @discardableResult
    static func activateAndShow(_ window: NSWindow?) -> Bool {
        guard let window, window.canBecomeKey else { return false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window.isKeyWindow
    }
}
