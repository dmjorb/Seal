import XCTest

final class RootNavigationUITests: XCTestCase {
    func testSwitchesBetweenTheTwoRootTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-empty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["应用"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        app.tabBars.buttons["应用"].tap()
        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 5))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Seal Root Navigation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
