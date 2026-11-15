import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WildcardsStudioView: View {
    @ObservedObject var coordinator: PromptenderCoordinator
    @ObservedObject var viewModel: PromptEngineViewModel

    @State private var searchQuery: String = ""
    @State private var selectedBankName: String = ""
    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var editTags: String = ""
    @State private var editItemsText: String = ""
    @State private var isCreatingNewBank: Bool = false
    @State private var lastRolledSample: String = ""
    @State private var isLoadingBank: Bool = false
    @State private var bankLoadError: String?
    @State private var bankLoadRequestID = UUID()
    @State private var isSavingBank: Bool = false
    @State private var isDeletingBank: Bool = false
    @State private var isSyncingBank: Bool = false
    @State private var pendingDeletion: WildcardBankRecord?
    @State private var pendingSync: WildcardSyncDraft?

    private var filteredBanks: [WildcardBankRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return coordinator.wildcardBanks }
        return coordinator.wildcardBanks.filter {
            $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            syncToolbarCard
            if let receipt = coordinator.latestWildcardOperationReceipt {
                wildcardOperationReceiptCard(receipt)
            }

            HStack(alignment: .top, spacing: 10) {
                bankListSidebar
                    .frame(width: 175)

                bankEditorPane
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectedBankName.isEmpty, let first = coordinator.wildcardBanks.first {
                selectBank(first)
            }
        }
        .sheet(item: $pendingDeletion) { bank in
            WildcardDeleteConfirmationSheet(
                bankName: bank.name,
                hasLocal: coordinator.wildcardStore.hasLocalBank(name: bank.name),
                hasFolder: coordinator.wildcardStore.hasSyncedBank(name: bank.name),
                hasRemote: coordinator.dexDiffusionWildcards.contains {
                    $0.name.lowercased() == bank.name.lowercased()
                },
                onCancel: { pendingDeletion = nil },
                onDelete: { local, folder, remote in
                    pendingDeletion = nil
                    isDeletingBank = true
                    Task {
                        let success = await coordinator.deleteWildcardBank(
                            name: bank.name, local: local, syncedFolder: folder, remote: remote
                        )
                        isDeletingBank = false
                        if success {
                            if let remaining = coordinator.wildcardBanks.first(where: { $0.id == bank.id }) {
                                selectBank(remaining)
                            } else if let next = coordinator.wildcardBanks.first {
                                selectBank(next)
                            } else {
                                selectedBankName = ""
                            }
                        }
                    }
                }
            )
        }
        .sheet(item: $pendingSync) { draft in
            WildcardSyncConfirmationSheet(
                bankName: draft.name,
                entryCount: draft.items.count,
                hasFolder: coordinator.wildcardStore.hasConfiguredSyncFolder,
                onCancel: { pendingSync = nil },
                onSync: { folder, remote, folderOverwrite, remoteOverwrite in
                    pendingSync = nil
                    isSyncingBank = true
                    Task {
                        let success = await coordinator.syncWildcardBank(
                            name: draft.name, items: draft.items, description: draft.description,
                            tags: draft.tags, toFolder: folder, toRemote: remote,
                            allowFolderOverwrite: folderOverwrite,
                            allowRemoteOverwrite: remoteOverwrite
                        )
                        isSyncingBank = false
                        if success, let refreshed = coordinator.wildcardBanks.first(where: { $0.id == draft.name.lowercased() }) {
                            selectBank(refreshed)
                        }
                    }
                }
            )
        }
    }

    private var syncToolbarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WILDCARDS · BUILT-IN & DEXTER FUSION SYNC")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(coordinator.wildcardBanks.count) banks available · __token__ format compatible with Dexter Fusion")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Bank") {
                    startNewBank()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await coordinator.refreshDexDiffusionStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minWidth: 44, minHeight: 44)
                .help("Refresh DexDiffusion wildcard catalog")
                .accessibilityLabel("Refresh DexDiffusion wildcard catalog")
                .disabled(coordinator.isRefreshingCapabilities)
            }

            HStack(spacing: 6) {
                Text("Folder Sync:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Optional Dexter Fusion wildcards directory path", text: Binding(
                    get: { coordinator.wildcardSyncDirectoryPath },
                    set: { coordinator.setWildcardSyncDirectory($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption2)

                Button("Browse...") {
                    browseSyncFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .glassCard()
    }

    private func wildcardOperationReceiptCard(_ receipt: WildcardOperationReceipt) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(receipt.completed, id: \.self) { step in
                    Label(step, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                ForEach(receipt.failed, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(receipt.recoveryMessage)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let directory = receipt.backupDirectory,
                   FileManager.default.fileExists(atPath: directory.path) {
                    Button("Reveal Backups in Finder") {
                        coordinator.revealWildcardBackups()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.callout)
            .padding(.vertical, 6)
        } label: {
            Label(
                receipt.title,
                systemImage: receipt.failed.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.callout.weight(.semibold))
        }
        .padding(10)
        .background(PromptenderTheme.surface.opacity(0.52), in: RoundedRectangle(cornerRadius: 9))
    }

    private var bankListSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter banks...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)

            ScrollView {
                if filteredBanks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(searchQuery.isEmpty ? "No wildcard banks available" : "No banks match the filter")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Create Bank") { startNewBank() }
                            .buttonStyle(.bordered)
                    }
                    .padding(8)
                }
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredBanks) { bank in
                        let isSelected = !isCreatingNewBank && bank.name.lowercased() == selectedBankName.lowercased()
                        Button {
                            selectBank(bank)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(bank.name)
                                        .font(.caption2.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(bank.count)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Text(bank.source.badgeLabel)
                                    .font(.system(size: 9))
                                    .foregroundStyle(bank.source == .dexterFusion ? .mint : .cyan)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSelected ? Color.cyan.opacity(0.20) : Color.clear)
                            .glassInset(cornerRadius: 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 240, maxHeight: 360)
        }
        .padding(8)
        .glassCard()
    }

    private var bankEditorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCreatingNewBank || !selectedBankName.isEmpty {
                HStack(spacing: 8) {
                    if isCreatingNewBank {
                        TextField("new_bank_name", text: $editName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                    } else {
                        Text("__\(selectedBankName)__")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.cyan)
                    }

                    Spacer()

                    Button("Insert Token") {
                        let targetName = isCreatingNewBank ? editName : selectedBankName
                        guard !targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let sep = viewModel.roughInput.isEmpty || viewModel.roughInput.hasSuffix(" ") ? "" : ", "
                        viewModel.roughInput += "\(sep)__\(targetName)__"
                        coordinator.statusBanner = "Inserted __\(targetName)__ into Raw Input."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Roll Sample") {
                        let lines = currentEditorItems
                        if let pick = lines.randomElement() {
                            lastRolledSample = coordinator.expandWildcardTokens(in: pick)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(currentEditorItems.isEmpty)
                }

                if !lastRolledSample.isEmpty {
                    Text("Sample: \(lastRolledSample)")
                        .font(.caption2)
                        .foregroundStyle(.mint)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassInset(cornerRadius: 6)
                }

                TextField("Description (optional)", text: $editDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)

                TextField("Tags (comma-separated)", text: $editTags)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)

                HStack {
                    Text("Entries (one option per line, # comments ignored)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isLoadingBank {
                        Text("Loading full bank...")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                    } else {
                        Text("\(currentEditorItems.count) items")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let bankLoadError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(bankLoadError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry Full Bank Load") {
                            if let bank = coordinator.wildcardBanks.first(where: {
                                $0.id == selectedBankName.lowercased()
                            }) {
                                selectBank(bank)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                TextEditor(text: $editItemsText)
                    .disabled(isLoadingBank || bankLoadError != nil)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 150, maxHeight: 230)
                    .padding(4)
                    .glassInset(cornerRadius: 6)

                HStack(spacing: 8) {
                    Menu("Bank Actions") {
                        Button("Import .txt...") { importTxtIntoEditor() }
                            .disabled(isLoadingBank || isSavingBank || isSyncingBank)
                        if !isCreatingNewBank && !selectedBankName.isEmpty {
                            Divider()
                            Button("Delete Bank...", role: .destructive) {
                                pendingDeletion = coordinator.wildcardBanks.first {
                                    $0.id == selectedBankName.lowercased()
                                }
                            }
                            .disabled(isDeletingBank || isSavingBank || isSyncingBank
                                || coordinator.wildcardStore.isBundledBank(name: selectedBankName))
                        }
                    }
                    .controlSize(.regular)
                    .frame(minHeight: 44)

                    Spacer(minLength: 4)

                    Button(isSavingBank ? "Saving..." : "Save Local") {
                        saveCurrentBank()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(effectiveBankName.isEmpty || coordinator.wildcardStore.isBundledBank(name: effectiveBankName) ? .gray : .accentColor)
                    .controlSize(.regular)
                    .frame(minHeight: 44)
                    .disabled(isSavingBank || isDeletingBank || isSyncingBank || isLoadingBank
                        || bankLoadError != nil || effectiveBankName.isEmpty
                        || coordinator.wildcardStore.isBundledBank(name: effectiveBankName))

                    Button(isSyncingBank ? "Syncing..." : "Sync...") {
                        let name = effectiveBankName
                        guard !name.isEmpty else { return }
                        pendingSync = WildcardSyncDraft(
                            name: name, items: currentEditorItems,
                            description: editDescription,
                            tags: editTags.split(separator: ",").map {
                                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            }.filter { !$0.isEmpty }
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(minHeight: 44)
                    .disabled(isSavingBank || isDeletingBank || isSyncingBank || isLoadingBank
                        || bankLoadError != nil || effectiveBankName.isEmpty
                        || coordinator.wildcardStore.isBundledBank(name: effectiveBankName))
                }
                if coordinator.wildcardStore.isBundledBank(name: effectiveBankName) {
                    Text("Bundled bank: read-only. Create a new bank to customize it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a wildcard bank on the left or click New Bank to author and sync custom __wildcards__ with Dexter Fusion.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .padding(10)
        .glassCard()
    }

    private var effectiveBankName: String {
        (isCreatingNewBank ? editName : selectedBankName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentEditorItems: [String] {
        editItemsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func selectBank(_ bank: WildcardBankRecord) {
        isCreatingNewBank = false
        selectedBankName = bank.name
        editName = bank.name
        editDescription = bank.description
        editTags = bank.tags.joined(separator: ", ")
        editItemsText = bank.items.joined(separator: "\n")
        lastRolledSample = ""
        bankLoadError = nil
        bankLoadRequestID = UUID()
        isLoadingBank = false

        if !bank.isFullDetailLoaded || bank.items.count < bank.count {
            isLoadingBank = true
            let bankName = bank.name
            let requestID = bankLoadRequestID
            Task {
                let full = await coordinator.loadWildcardBankDetail(name: bankName)
                guard requestID == bankLoadRequestID,
                      selectedBankName.lowercased() == bankName.lowercased() else { return }
                isLoadingBank = false
                if let full, full.isFullDetailLoaded, full.items.count >= full.count {
                    editDescription = full.description
                    editTags = full.tags.joined(separator: ", ")
                    editItemsText = full.items.joined(separator: "\n")
                    bankLoadError = nil
                } else {
                    bankLoadError = "Complete bank unavailable. The displayed entries may be a preview. Refresh DexDiffusion before editing or syncing."
                }
            }
        }
    }

    private func startNewBank() {
        bankLoadRequestID = UUID()
        bankLoadError = nil
        isLoadingBank = false
        isCreatingNewBank = true
        selectedBankName = ""
        editName = ""
        editDescription = ""
        editTags = ""
        editItemsText = ""
        lastRolledSample = ""
    }

    private func saveCurrentBank() {
        let name = effectiveBankName
        guard !name.isEmpty else { return }
        let tags = editTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let items = editItemsText.components(separatedBy: .newlines)
        isSavingBank = true
        Task {
            defer { isSavingBank = false }
            let saved = await coordinator.saveWildcardBank(name: name, items: items, description: editDescription, tags: tags)
            if saved {
                isCreatingNewBank = false
                selectedBankName = name
                if let refreshed = coordinator.wildcardBanks.first(where: { $0.id == name.lowercased() }) {
                    selectBank(refreshed)
                }
            }
        }
    }

    private func browseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Dexter Fusion Wildcards Directory"
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.setWildcardSyncDirectory(url.path)
        }
    }

    private func importTxtIntoEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url,
           let content = try? String(contentsOf: url, encoding: .utf8) {
            let lines = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            if editItemsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                editItemsText = lines.joined(separator: "\n")
            } else {
                editItemsText += "\n" + lines.joined(separator: "\n")
            }
        }
    }
}


private struct WildcardSyncDraft: Identifiable {
    let id = UUID()
    let name: String
    let items: [String]
    let description: String
    let tags: [String]
}

private struct WildcardDeleteConfirmationSheet: View {
    let bankName: String
    let hasLocal: Bool
    let hasFolder: Bool
    let hasRemote: Bool
    let onCancel: () -> Void
    let onDelete: (Bool, Bool, Bool) -> Void

    @State private var deleteLocal: Bool
    @State private var deleteFolder: Bool = false
    @State private var deleteRemote: Bool = false
    @State private var acknowledgeRemote: Bool = false

    init(
        bankName: String, hasLocal: Bool, hasFolder: Bool, hasRemote: Bool,
        onCancel: @escaping () -> Void,
        onDelete: @escaping (Bool, Bool, Bool) -> Void
    ) {
        self.bankName = bankName
        self.hasLocal = hasLocal
        self.hasFolder = hasFolder
        self.hasRemote = hasRemote
        self.onCancel = onCancel
        self.onDelete = onDelete
        _deleteLocal = State(initialValue: hasLocal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Delete __\(bankName)__?")
                .font(.headline)
            Text("Choose precisely which copies to remove. No remote or synced-folder copy is deleted by default. Existing files are backed up before deletion.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Local DEX//PROMPTENDER copy", isOn: $deleteLocal)
                .disabled(!hasLocal)
            Toggle("External synced-folder copy", isOn: $deleteFolder)
                .disabled(!hasFolder)
            Toggle("DexDiffusion remote bank (live DELETE request)", isOn: $deleteRemote)
                .disabled(!hasRemote)
            if deleteRemote {
                Toggle("I understand this deletes the remote bank after backing it up locally.", isOn: $acknowledgeRemote)
                    .font(.caption)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete Selected Copies", role: .destructive) {
                    onDelete(deleteLocal, deleteFolder, deleteRemote)
                }
                .disabled(!(deleteLocal || deleteFolder || deleteRemote)
                    || (deleteRemote && !acknowledgeRemote))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 440, maxWidth: 470)
    }
}

private struct WildcardSyncConfirmationSheet: View {
    let bankName: String
    let entryCount: Int
    let hasFolder: Bool
    let onCancel: () -> Void
    let onSync: (Bool, Bool, Bool, Bool) -> Void

    @State private var toFolder = false
    @State private var toRemote = false
    @State private var allowFolderOverwrite = false
    @State private var allowRemoteOverwrite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync __\(bankName)__")
                .font(.headline)
            Text("\(entryCount) entries. Saving locally never syncs automatically. Select an external destination explicitly.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Mirror into configured synced folder", isOn: $toFolder)
                .disabled(!hasFolder)
            if toFolder {
                Toggle("Allow replacing a DIFFERENT folder copy (backup first)", isOn: $allowFolderOverwrite)
                    .font(.caption)
            }
            Toggle("Push to DexDiffusion (live PUT request)", isOn: $toRemote)
            if toRemote {
                Toggle("Allow replacing a DIFFERENT remote bank (backup first)", isOn: $allowRemoteOverwrite)
                    .font(.caption)
            }

            Text("Existing destination data is compared first. If it differs, an unchecked overwrite permission blocks the operation.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Local & Sync Selected") {
                    onSync(toFolder, toRemote, allowFolderOverwrite, allowRemoteOverwrite)
                }
                .disabled(!(toFolder || toRemote))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 440, maxWidth: 470)
    }
}
