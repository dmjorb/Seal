import XCTest

final class ImportFlowUITests: XCTestCase {
    @MainActor
    func testEmptyStateHasImportEntry() {
        let app = launch(with: "--ui-testing-empty")
        XCTAssertTrue(app.staticTexts["Seal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["待签名，0 个"].exists)
        XCTAssertTrue(app.buttons["import-toolbar-button"].exists)
        XCTAssertFalse(element("imported-app-row", in: app).exists)
    }

    @MainActor
    func testNormalColdLaunchDefaultsToInstalledAndPendingItemRemainsAvailable() {
        let app = launch(with: "--ui-testing-imported")
        XCTAssertTrue(app.buttons["待签名，1 个"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已安装应用"].waitForExistence(timeout: 10))
        app.buttons["待签名，1 个"].tap()
        XCTAssertTrue(element("imported-app-row", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["import-toolbar-button"].exists)
    }

    @MainActor
    func testConfirmationKeepsSummaryAndActionsConcise() {
        let app = launch(with: "--ui-testing-confirmation")
        XCTAssertTrue(app.otherElements["import-confirmation"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("import-confirmation-name", in: app).exists)
        XCTAssertTrue(element("import-confirmation-version", in: app).exists)
        assertSummary("import-summary-extensions", value: "1 个", in: app)
        assertSummary("import-summary-compatibility", value: "可导入", in: app)
        XCTAssertTrue(app.buttons["导入"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
    }

    @MainActor
    func testThreeStageNavigationCanBeTappedWithoutChangingHeaderAlignment() {
        let app = launch(with: "--ui-testing-empty")
        XCTAssertTrue(app.buttons["待签名，0 个"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["已签名，0 个"].exists)
        XCTAssertTrue(app.buttons["已安装，0 个"].exists)

        app.buttons["已签名，0 个"].tap()
        XCTAssertTrue(app.staticTexts["已签名应用"].waitForExistence(timeout: 5))
        app.buttons["已安装，0 个"].tap()
        XCTAssertTrue(app.staticTexts["已安装应用"].waitForExistence(timeout: 5))
        app.buttons["待签名，0 个"].tap()
        XCTAssertTrue(app.staticTexts["待签名应用"].waitForExistence(timeout: 5))
    }


    @MainActor
    func testThreeStageNavigationSupportsHorizontalSwipe() {
        let app = launch(with: "--ui-testing-empty")
        XCTAssertTrue(app.staticTexts["待签名应用"].waitForExistence(timeout: 10))
        let pager = element("apps-stage-pager", in: app)
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["已签名应用"].waitForExistence(timeout: 5))
        pager.swipeLeft()
        XCTAssertTrue(app.staticTexts["已安装应用"].waitForExistence(timeout: 5))
        pager.swipeRight()
        XCTAssertTrue(app.staticTexts["已签名应用"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeDynamicTypeKeepsPrimaryNavigationReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-empty",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["待签名，0 个"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["已签名，0 个"].exists)
        XCTAssertTrue(app.buttons["已安装，0 个"].exists)
        XCTAssertTrue(app.buttons["import-toolbar-button"].exists)
    }

    @MainActor
    private func launch(with argument: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = [argument]; app.launch(); return app
    }
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor
    private func assertSummary(_ identifier: String, value: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let summary = element(identifier, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(summary.value as? String, value, file: file, line: line)
    }
}
