import Testing
@testable import PromptenderKit

@Suite("Bootstrap Smoke")
struct BootstrapSmokeTests {
    @Test("App bundle resource lookup resolves DefaultTemplates")
    func resourceLookupWorks() {
        let url = AppBundleResources.url(forResource: "DefaultTemplates", withExtension: "json")
        #expect(url != nil)
    }
}
