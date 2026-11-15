import AppKit
import SwiftUI
import Testing
@testable import PromptenderKit

@MainActor
private final class KeyboardBindingProbe: ObservableObject {
    @Published var title = ""
    @Published var secret = ""
    @Published var notes = ""
    @Published var rawPrompt = ""
}

private struct HostedKeyboardControls: View {
    @ObservedObject var model: KeyboardBindingProbe

    var body: some View {
        VStack(spacing: 8) {
            TextField("Plain test field", text: $model.title)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret test field", text: $model.secret)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $model.notes)
                .frame(height: 70)
            TransparentTextEditor(text: $model.rawPrompt)
                .frame(height: 70)
        }
        .padding()
    }
}

@Suite("Hosted Native Keyboard Controls", .serialized)
struct HostedNativeKeyboardControlsTests {
    private func allViews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allViews(in: $0) }
    }

    @MainActor
    @Test("SwiftUI input fields and custom NSTextView can all receive keyboard input")
    func editorBindingsAcceptKeyboardEvents() async throws {
        _ = NSApplication.shared
        let model = KeyboardBindingProbe()
        let host = NSHostingView(rootView: HostedKeyboardControls(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 450, height: 300)

        let panel = NSPanel(
            contentRect: NSRect(x: 120, y: 150, width: 450, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        defer { panel.close() }
        _ = PromptenderWindowFocus.activateAndShow(panel)
        host.layoutSubtreeIfNeeded()
        let descendents = allViews(in: host)
        let fields = descendents.compactMap { $0 as? NSTextField }
        let editors = descendents.compactMap { $0 as? NSTextView }
        let plain = try #require(fields.first { $0.placeholderString == "Plain test field" })
        let secure = try #require(fields.first { $0.placeholderString == "Secret test field" })
        let raw = try #require(editors.first { $0.accessibilityLabel() == "Raw prompt" })
        let notes = try #require(editors.first { $0 !== raw })

        func type(_ value: String) throws {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: NSPoint(x: 32, y: 32),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: value,
                charactersIgnoringModifiers: value, isARepeat: false, keyCode: 0
            ) else { throw NSError(domain: "Keyboard", code: 4) }
            panel.sendEvent(event)
        }

        #expect(panel.makeFirstResponder(plain))
        try type("t")
        try await Task.sleep(for: .milliseconds(80))
        #expect(plain.stringValue == "t")
        #expect(model.title == "t")

        #expect(panel.makeFirstResponder(secure))
        try type("s")
        try await Task.sleep(for: .milliseconds(80))
        #expect(secure.stringValue == "s")
        #expect(model.secret == "s")

        #expect(panel.makeFirstResponder(notes))
        try type("n")
        try await Task.sleep(for: .milliseconds(80))
        #expect(notes.string == "n")
        #expect(model.notes == "n")

        #expect(panel.makeFirstResponder(raw))
        try type("r")
        try await Task.sleep(for: .milliseconds(80))
        #expect(raw.string == "r")
        #expect(model.rawPrompt == "r")
    }
}
