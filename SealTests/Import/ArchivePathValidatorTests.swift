import Testing
@testable import Seal

struct ArchivePathValidatorTests {
    @Test(arguments: [
        "Payload/Demo.app/Info.plist",
        "Payload/Demo.app/PlugIns/Share.appex/Info.plist"
    ])
    func acceptsRelativeIPAPaths(path: String) {
        #expect(ArchivePathValidator.isSafe(path) == true)
    }

    @Test(arguments: [
        "/Payload/Demo.app/Info.plist",
        "../outside",
        "Payload/../outside",
        "Payload\\Demo.app\\Info.plist",
        "C:/Payload/Demo.app/Info.plist"
    ])
    func rejectsTraversalAndPlatformSpecificPaths(path: String) {
        #expect(ArchivePathValidator.isSafe(path) == false)
    }
}
