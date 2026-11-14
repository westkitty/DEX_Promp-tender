import SwiftUI

struct DexPromptenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

public enum DexPromptenderEntryPoint {
    public static func run() {
        DexPromptenderApp.main()
    }
}
