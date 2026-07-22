import XCTest

final class ImportFlowUITests: XCTestCase {
    func testEmptyStateHasImportEntry() {
        let app = launch(with: "--ui-testing-empty")
        XCTAssertTrue(app.buttons["import-toolbar-button"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["待签名，0 个"].exists)
        XCTAssertFalse(element("imported-app-row", in: app).exists)
    }

    func testImportedStateAppearsInPendingList() {
        let app = launch(with: "--ui-testing-imported")
        XCTAssertTrue(app.buttons["待签名，1 个"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("imported-app-row", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["import-toolbar-button"].exists)
    }

    func testConfirmationKeepsSummaryAndActionsConcise() {
        let app = launch(with: "--ui-testing-confirmation")
        let confirmation = app.otherElements["import-confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        XCTAssertTrue(confirmation.staticTexts["导入 IPA"].exists)
        XCTAssertTrue(confirmation.staticTexts["Demo"].exists)
        XCTAssertTrue(
            confirmation.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "v1.0 · "))
                .firstMatch
                .exists
        )
        XCTAssertTrue(confirmation.staticTexts["Bundle ID"].exists)
        XCTAssertTrue(confirmation.staticTexts["com.example.demo"].exists)
        XCTAssertTrue(confirmation.staticTexts["扩展"].exists)
        XCTAssertTrue(confirmation.staticTexts["1 个"].exists)
        XCTAssertTrue(confirmation.staticTexts["状态"].exists)
        XCTAssertTrue(confirmation.staticTexts["可导入"].exists)
        XCTAssertTrue(confirmation.buttons["导入"].exists)
        XCTAssertTrue(confirmation.buttons["取消"].exists)
    }

    private func launch(with argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            argument,
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN"
        ]
        app.launch()
        return app
    }
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
}
