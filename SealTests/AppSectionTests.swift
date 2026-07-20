import XCTest
@testable import Seal

final class AppSectionTests: XCTestCase {
    func testRootSectionsMatchTheTwoEntryPointNavigation() {
        XCTAssertEqual(AppSection.allCases, [.apps, .settings])
    }

    func testRootSectionTitlesAreConciseChinese() {
        XCTAssertEqual(AppSection.apps.title, "应用")
        XCTAssertEqual(AppSection.settings.title, "设置")
    }

    func testRootSectionIconsAreStable() {
        XCTAssertEqual(AppSection.apps.systemImage, "square.grid.2x2")
        XCTAssertEqual(AppSection.settings.systemImage, "gearshape.fill")
    }

    func testMissingAccountSetupOpensAddAccountDirectly() {
        XCTAssertEqual(SettingsRoute(EnvironmentSetupStep.account), .addAccount)
        XCTAssertEqual(SettingsRoute(EnvironmentSetupStep.pairing), .pairing)
    }
}
