import AppKit
import SwiftUI
import Foundation
import Testing
@testable import PromptenderKit

@Suite("Impeccable Native Layout Probe")
struct ImpeccableNativeLayoutProbeTests {
    @MainActor
    @Test("Root popover captures compact, narrow-output, and split-output layouts")
    func snapshotLayouts() throws {
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptender-impeccable-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        for (width, height, openResult) in [(480, 660, false), (720, 560, true), (960, 660, true)] {
            let folderName = "DexPromptender-UIProbe-\(UUID().uuidString)"
            let appSupportFolder = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent(folderName, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: appSupportFolder) }

            let viewModel = PromptEngineViewModel(
                storageManager: StorageManager(appFolderName: folderName),
                promptLibraryRepository: PromptLibraryRepository(storageBackend: InMemoryStorageBackend())
            )
            let coordinator = PromptenderCoordinator(
                recipeStore: RecipeStore(storageDirectoryURL: testDir),
                wildcardStore: WildcardStore(storageDirectoryURL: testDir),
                secretStore: InMemorySecretStore()
            )
            let appearance = AppearanceSettingsStore(
                fileURL: testDir.appendingPathComponent("appearance-\(width).json")
            )
            viewModel.roughInput = "Compose a photographic scene of a violet cup on a white shelf, carefully preserving the subject's exact outline and the requested number of separate outputs."
            let result = coordinator.mixPrompt(
                rawInput: viewModel.roughInput,
                variables: viewModel.variableValues,
                legacyOptions: viewModel.options
            )
            viewModel.generatedPrompt = result.compiledPrompt
            viewModel.isResultPanelVisible = openResult

            let host = NSHostingView(
                rootView: RootPopoverView(
                    viewModel: viewModel, coordinator: coordinator, appearance: appearance
                )
            )
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                Issue.record("No bitmap for width \(width)")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                Issue.record("No PNG at width \(width)")
                continue
            }
            let destination = URL(fileURLWithPath: "/tmp/dexpromptender-impeccable-\(width).png")
            try png.write(to: destination)
            #expect(png.count > 3000)
            #expect(bitmap.pixelsWide == width)
            #expect(bitmap.pixelsHigh == height)
        }
    }


    @MainActor
    @Test("Wildcard editor, settings and Serve confirmation can render without a live backend")
    func snapshotSecondarySurfaces() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptender-secondary-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let folderName = "DexPromptender-UIProbe-\(UUID().uuidString)"
        let appSupportFolder = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent(folderName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupportFolder) }

        let viewModel = PromptEngineViewModel(
            storageManager: StorageManager(appFolderName: folderName),
            promptLibraryRepository: PromptLibraryRepository(storageBackend: InMemoryStorageBackend())
        )
        let coordinator = PromptenderCoordinator(
            recipeStore: RecipeStore(storageDirectoryURL: tempDir),
            wildcardStore: WildcardStore(storageDirectoryURL: tempDir),
            secretStore: InMemorySecretStore()
        )
        let appearance = AppearanceSettingsStore(
            fileURL: tempDir.appendingPathComponent("appearance.json")
        )
        viewModel.roughInput = "Editorial photograph of a cobalt vase, no other subjects"
        _ = coordinator.mixPrompt(
            rawInput: viewModel.roughInput,
            variables: viewModel.variableValues,
            legacyOptions: viewModel.options
        )
        coordinator.requestExternalServe(
            channel: .submitDexDiffusionControlled,
            rawInput: viewModel.roughInput,
            variables: viewModel.variableValues,
            legacyOptions: viewModel.options
        )

        var surfaces: [(String, AnyView, Int, Int)] = [
            ("wildcards", AnyView(WildcardsStudioView(coordinator: coordinator, viewModel: viewModel)), 480, 660),
            ("settings", AnyView(PromptenderSettingsView(
                coordinator: coordinator, viewModel: viewModel, appearance: appearance
            )), 480, 1540)
        ]
        if let confirmation = coordinator.pendingServeConfirmation {
            surfaces.append(("serve", AnyView(ServeConfirmationSheet(
                coordinator: coordinator, confirmation: confirmation, viewModel: viewModel
            )), 560, 620))
        } else {
            Issue.record("Expected a mock-only Serve confirmation")
        }

        for (name, view, width, height) in surfaces {
            let surface = ZStack {
                Color(red: 0.10, green: 0.14, blue: 0.16).ignoresSafeArea()
                view
            }
            .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: surface)
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds),
                  bitmap.pixelsWide == width,
                  bitmap.pixelsHigh == height else {
                Issue.record("No correctly sized bitmap for \(name)")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                Issue.record("Could not encode \(name)")
                continue
            }
            try png.write(to: URL(fileURLWithPath: "/tmp/dexpromptender-impeccable-\(name).png"))
            #expect(png.count > 3000)
        }
    }

}
