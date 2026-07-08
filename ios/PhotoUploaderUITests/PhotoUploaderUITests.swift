import XCTest

/// Smoke tests that drive the app in the simulator and attach screenshots,
/// so CI can verify (and show) the UI without a local Mac.
final class PhotoUploaderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSetupThenAuthScreens() throws {
        let app = XCUIApplication()

        // First launch (fresh install): the setup screen is shown. Assert on
        // the guide entry at the top of the form — rows further down (like
        // the manual-input fields) may not exist yet because Form loads its
        // rows lazily and off-screen rows are not materialized.
        app.launch()
        attachScreenshot(named: "00-splash")
        sleep(3)
        let guideEntry = app.staticTexts["はじめての方はこちら(設定ガイド)"]
        XCTAssertTrue(guideEntry.waitForExistence(timeout: 10), "接続先設定画面が表示されること")
        attachScreenshot(named: "01-setup")

        // Open the first-time guide and capture it too.
        guideEntry.tap()
        sleep(1)
        attachScreenshot(named: "01b-guide")
        app.terminate()

        // Relaunch with a preset backend config (typing into the simulator is
        // flaky in CI) to verify the sign-in / sign-up screens.
        app.launchArguments = ["-uiTestPresetConfig"]
        app.launch()
        sleep(3)
        XCTAssertTrue(
            app.textFields["メールアドレス"].waitForExistence(timeout: 10),
            "ログイン画面が表示されること"
        )
        XCTAssertTrue(app.secureTextFields["パスワード(8文字以上)"].exists)
        attachScreenshot(named: "02-sign-in")

        let signUpSegment = app.segmentedControls.buttons["新規登録"]
        if signUpSegment.waitForExistence(timeout: 5) {
            signUpSegment.tap()
            XCTAssertTrue(app.buttons["登録する"].waitForExistence(timeout: 5))
            attachScreenshot(named: "03-sign-up")
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
