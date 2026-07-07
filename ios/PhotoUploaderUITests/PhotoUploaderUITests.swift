import XCTest

/// Smoke tests that drive the app in the simulator and attach screenshots,
/// so CI can verify (and show) the UI without a local Mac.
final class PhotoUploaderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testMainScreenShowsEmptyStateAndPicker() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Photo Uploader"].waitForExistence(timeout: 10),
            "ナビゲーションバーが表示されること"
        )
        XCTAssertTrue(app.buttons["写真を選択"].exists, "写真選択ボタンが表示されること")
        XCTAssertTrue(app.staticTexts["写真がありません"].exists, "空状態の案内が表示されること")

        attachScreenshot(named: "01-empty-state")

        // Open the photo picker (an out-of-process sheet) and capture it.
        app.buttons["写真を選択"].tap()
        sleep(3)
        attachScreenshot(named: "02-photo-picker")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
