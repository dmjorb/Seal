import XCTest

final class RootNavigationUITests: XCTestCase {
    func testSwitchesBetweenTheTwoRootTabs() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-empty",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["import-toolbar-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["应用"].exists)
        XCTAssertTrue(app.tabBars.buttons["我的"].exists)

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))

        app.tabBars.buttons["应用"].tap()
        XCTAssertTrue(app.buttons["import-toolbar-button"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Seal Root Navigation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
