import Foundation

enum AppBundleResources {
    static func url(forResource name: String, withExtension ext: String?) -> URL? {
        if let mainURL = Bundle.main.url(forResource: name, withExtension: ext) {
            return mainURL
        }
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: ext)
        #else
        return nil
        #endif
    }
}
