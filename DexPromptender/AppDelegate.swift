import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let collapsedSize = NSSize(width: 480, height: 660)
    private let expandedSize = NSSize(width: 960, height: 660)
    private let detachedSize = NSSize(width: 1080, height: 720)

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var toggleDrawerMenuItem: NSMenuItem!
    private var popover: NSPopover!
    private var detachedWindow: NSPanel?
    private var localChatWindow: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private lazy var coordinator: PromptenderCoordinator = {
        MainActor.assumeIsolated {
            PromptenderCoordinator()
        }
    }()

    private lazy var appearanceStore: AppearanceSettingsStore = {
        MainActor.assumeIsolated {
            AppearanceSettingsStore()
        }
    }()

    private lazy var viewModel: PromptEngineViewModel = {
        let vm = PromptEngineViewModel()
        vm.onRevealStateChanged = { [weak self] expanded in
            self?.resizePopover(expanded: expanded, animated: true)
            self?.updateDetachedWindowMinimumSize(expanded: expanded)
        }
        vm.onDetachedWindowToggleRequested = { [weak self] in
            self?.toggleDetachedWindow()
        }
        vm.onLocalChatWindowToggleRequested = { [weak self] in
            self?.toggleLocalChatWindow()
        }
        return vm
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPopover()
        setupStatusItem()
        setupKeyboardShortcut()
        Task { @MainActor in
            await coordinator.refreshDexDiffusionStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = collapsedSize

        let rootView = RootPopoverView(viewModel: viewModel, coordinator: coordinator, appearance: appearanceStore)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }
        button.title = ""
        button.toolTip = "DEX//PROMPTENDER"
        let icon = NSImage(systemSymbolName: "wineglass.fill", accessibilityDescription: "DEX//PROMPTENDER")
            ?? NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "DEX//PROMPTENDER")
        if let icon {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            button.image = icon.withSymbolConfiguration(symbolConfig)
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
        }
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self

        setupStatusMenu()
    }

    private func setupStatusMenu() {
        let menu = NSMenu()

        toggleDrawerMenuItem = NSMenuItem(title: "Open Bar", action: #selector(togglePopover(_:)), keyEquivalent: "")
        toggleDrawerMenuItem.target = self
        menu.addItem(toggleDrawerMenuItem)

        let mixingRoomItem = NSMenuItem(title: "Open Mixing Room", action: #selector(openMixingRoomFromMenu(_:)), keyEquivalent: "m")
        mixingRoomItem.target = self
        menu.addItem(mixingRoomItem)

        let refreshDexItem = NSMenuItem(title: "Refresh DexDiffusion Status", action: #selector(refreshDexDiffusionFromMenu(_:)), keyEquivalent: "")
        refreshDexItem.target = self
        menu.addItem(refreshDexItem)

        menu.addItem(.separator())

        let batchExportItem = NSMenuItem(title: "Run Batch Export", action: #selector(runBatchExport(_:)), keyEquivalent: "")
        batchExportItem.target = self
        menu.addItem(batchExportItem)

        let quitItem = NSMenuItem(title: "Quit DEX//PROMPTENDER", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusMenu = menu
    }

    @objc private func openMixingRoomFromMenu(_ sender: Any?) {
        if detachedWindow == nil {
            openDetachedWindow()
        } else {
            detachedWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func refreshDexDiffusionFromMenu(_ sender: Any?) {
        Task { @MainActor in
            await coordinator.refreshDexDiffusionStatus()
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            toggleDrawerMenuItem.title = popover.isShown ? "Close Bar" : "Open Bar"
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func runBatchExport(_ sender: Any?) {
        do {
            let baseDir = BatchExportService.appSupportDirURL()
            try BatchExportService.ensureDirExists(baseDir)

            let inputURL = BatchExportService.inputsURL()
            let outputURL = BatchExportService.outputsURL()
            let fileManager = FileManager.default

            if !fileManager.fileExists(atPath: inputURL.path) {
                try BatchExportService.writeBatchInputsTemplate(to: inputURL)
                showRevealAlert(
                    title: "Created batch inputs template",
                    message: "Template created at:\n\(inputURL.path)",
                    revealURL: baseDir
                )
                return
            }

            let summary = try BatchExportService.runBatchExport(inputsURL: inputURL, outputsURL: outputURL)
            showRevealAlert(
                title: "Batch export complete",
                message: "Processed: \(summary.processedCount)\nFailures: \(summary.failureCount)\nOutput: \(outputURL.path)",
                revealURL: baseDir
            )
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Batch export failed."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func showRevealAlert(title: String, message: String, revealURL: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([revealURL])
        }
    }

    private func setupKeyboardShortcut() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isToggleShortcut(event) else { return }
            DispatchQueue.main.async {
                self.togglePopover(nil)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isToggleShortcut(event) {
                self.togglePopover(nil)
                return nil
            }
            return event
        }
    }

    private func isToggleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let required: NSEvent.ModifierFlags = [.command, .shift]
        let disallowed: NSEvent.ModifierFlags = [.control, .option]

        return event.keyCode == 49 && flags.isSuperset(of: required) && flags.intersection(disallowed).isEmpty
    }

    @objc private func togglePopover(_ sender: Any?) {
        if viewModel.isDetachedWindowActive {
            detachedWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            resizePopover(expanded: viewModel.isResultPanelVisible, animated: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func toggleDetachedWindow() {
        if detachedWindow == nil {
            openDetachedWindow()
        } else {
            closeDetachedWindow(showPopoverAfterClose: true)
        }
    }

    private func toggleLocalChatWindow() {
        if localChatWindow == nil {
            openLocalChatWindow()
        } else {
            closeLocalChatWindow()
        }
    }

    private func openDetachedWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }

        let minWidth: CGFloat = 880
        let rect = NSRect(x: 0, y: 0, width: detachedSize.width, height: detachedSize.height)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "DEX//PROMPTENDER · The Mixing Room"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.minSize = NSSize(width: minWidth, height: 580)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: RootPopoverView(viewModel: viewModel, coordinator: coordinator, appearance: appearanceStore)
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        detachedWindow = panel
        viewModel.setDetachedWindowActive(true)
    }

    private func closeDetachedWindow(showPopoverAfterClose: Bool) {
        guard let window = detachedWindow else { return }
        window.close()

        if showPopoverAfterClose, let button = statusItem.button {
            resizePopover(expanded: viewModel.isResultPanelVisible, animated: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openLocalChatWindow() {
        let rect = NSRect(x: 0, y: 0, width: 460, height: 640)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = "DEX//PROMPTENDER Local Chat"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        panel.minSize = NSSize(width: 420, height: 520)
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: LocalChatPanelView(viewModel: viewModel)
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        localChatWindow = panel
        viewModel.setLocalChatWindowActive(true)
    }

    private func closeLocalChatWindow() {
        guard let window = localChatWindow else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        if closingWindow == detachedWindow {
            detachedWindow = nil
            viewModel.setDetachedWindowActive(false)
        }

        if closingWindow == localChatWindow {
            localChatWindow = nil
            viewModel.setLocalChatWindowActive(false)
        }
    }

    private func updateDetachedWindowMinimumSize(expanded: Bool) {
        guard let window = detachedWindow else { return }
        window.minSize = NSSize(width: 880, height: 580)
    }

    private func resizePopover(expanded: Bool, animated: Bool) {
        let targetSize = expanded ? expandedSize : collapsedSize

        guard popover.isShown,
              let window = popover.contentViewController?.view.window
        else {
            popover.contentSize = targetSize
            return
        }

        var frame = window.frame
        let deltaWidth = targetSize.width - frame.width
        frame.origin.x -= deltaWidth
        frame.size = targetSize

        popover.contentSize = targetSize

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }
}

private struct LocalChatPanelView: View {
    @ObservedObject var viewModel: PromptEngineViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Local Prompt Chat")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clearLocalChat()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.localChatMessages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == .user ? "You" : "Local LLM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.content)
                                .font(.system(size: 13))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if message.role == .assistant {
                                HStack(spacing: 6) {
                                    Button("Use as Rough Input") {
                                        viewModel.applyLocalChatMessageToRoughInput(message.id, forgeImmediately: false)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Use + Forge") {
                                        viewModel.applyLocalChatMessageToRoughInput(message.id, forgeImmediately: true)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(message.role == .user ? 0.08 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the local model to help craft your prompt…", text: $viewModel.localChatInput, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.sendLocalChatMessage()
                } label: {
                    if viewModel.isLocalChatGenerating {
                        ProgressView()
                    } else {
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLocalChatGenerating)
            }

            if !viewModel.localChatStatus.isEmpty {
                Text(viewModel.localChatStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(minWidth: 420, minHeight: 520, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }
}
