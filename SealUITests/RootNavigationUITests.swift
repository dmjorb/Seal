import XCTest

final class RootNavigationUITests: XCTestCase {
    @MainActor
    func testSwitchesBetweenTheTwoRootTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-empty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 10))
        let appsTab = app.buttons["root-tab-apps"]
        let settingsTab = app.buttons["root-tab-settings"]
        XCTAssertTrue(appsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))

        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))

        appsTab.tap()
        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Seal Root Navigation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
