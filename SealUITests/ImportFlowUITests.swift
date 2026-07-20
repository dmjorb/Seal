import XCTest

final class ImportFlowUITests: XCTestCase {
    func testEmptyStateHasImportEntry() {
        let app = launch(with: "--ui-testing-empty")
        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["待签名，0 个"].exists)
        XCTAssertTrue(app.buttons["import-toolbar-button"].exists)
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
        XCTAssertTrue(app.otherElements["import-confirmation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo"].exists)
        XCTAssertTrue(app.staticTexts["v1.0 (1)"].exists)
        assertSummary("import-summary-extensions", value: "1 个", in: app)
        assertSummary("import-summary-compatibility", value: "兼容", in: app)
        assertSummary("import-summary-account", value: "签名时选择", in: app)
        XCTAssertTrue(app.buttons["导入"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
    }

    private func launch(with argument: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = [argument]; app.launch(); return app
    }
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    private func assertSummary(_ identifier: String, value: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let summary = element(identifier, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(summary.value as? String, value, file: file, line: line)
    }
}
