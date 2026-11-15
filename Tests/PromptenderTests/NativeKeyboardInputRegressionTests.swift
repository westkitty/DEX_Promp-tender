import AppKit
import SwiftUI
import Testing
@testable import PromptenderKit

@MainActor
private final class FocusRequestWindow: NSWindow {
    var madeKeyRequest = false

    override func makeKey() {
        madeKeyRequest = true
        super.makeKey()
    }
}

@Suite("Native Keyboard Input Regression", .serialized)
struct NativeKeyboardInputRegressionTests {
    @MainActor
    private func sendTypedCharacter(_ value: String, into window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: NSPoint(x: 32, y: 32),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: value,
            charactersIgnoringModifiers: value.lowercased(),
            isARepeat: false,
            keyCode: 0
        ) else {
            throw NSError(domain: "KeyboardFocusProbe", code: 1)
        }
        window.sendEvent(event)
    }

    @MainActor
    @Test("Focus coordinator requests a key transition, not becomeKey callback")
    func requestsKeyWindowCorrectly() {
        _ = NSApplication.shared
        let window = FocusRequestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        _ = PromptenderWindowFocus.activateAndFocus(window)
        #expect(window.canBecomeKey)
        #expect(window.madeKeyRequest)
        // Actual key-window status depends on user activation.
    }

    @MainActor
    @Test("Detached editor routes keyDown into native text field and raw prompt editor")
    func detachedPanelReceivesTyping() throws {
        _ = NSApplication.shared
        let prompt = NSTextView(frame: NSRect(x: 15, y: 20, width: 260, height: 75))
        prompt.isEditable = true
        prompt.isSelectable = true
        prompt.string = ""
        let field = NSTextField(frame: NSRect(x: 15, y: 118, width: 260, height: 30))
        field.placeholderString = "Prompt name"

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 175))
        content.addSubview(prompt)
        content.addSubview(field)
        let panel = NSPanel(
            contentRect: NSRect(x: 90, y: 100, width: 310, height: 175),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = content
        defer { panel.close() }

        #expect(panel.canBecomeKey)
        _ = PromptenderWindowFocus.activateAndShow(panel)
        #expect(panel.makeFirstResponder(field))
        try sendTypedCharacter("s", into: panel)
        #expect(field.stringValue == "s")

        #expect(panel.makeFirstResponder(prompt))
        try sendTypedCharacter("r", into: panel)
        #expect(prompt.string == "r")
    }

    @Test("AppDelegate never invokes AppKit's becomeKey notification as a focus request")
    func noDirectBecomeKeyInvocation() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DexPromptender/AppDelegate.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        #expect(!text.contains(".becomeKey()"),
                "Use makeKey() to request focus, never invoke the becomeKey callback.")
    }

    @MainActor
    @Test("Keyboard focus helper is safe for missing windows")
    func missingWindowIsHandled() {
        #expect(!PromptenderWindowFocus.activateAndFocus(nil))
        #expect(!PromptenderWindowFocus.activateAndShow(nil))
    }
}
