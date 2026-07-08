import XCTest

/// Smoke tests that drive the app in the simulator and attach screenshots,
/// so CI can verify (and show) the UI without a local Mac.
final class PhotoUploaderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSetupThenAuthScreens() throws {
        let app = XCUIApplication()
        app.launch()

        // A fresh install has no backend configured, so setup comes first.
        let apiField = app.textFields["APIのURL"]
        XCTAssertTrue(apiField.waitForExistence(timeout: 10), "接続先設定画面が表示されること")
        attachScreenshot(named: "01-setup")

        apiField.tap()
        apiField.typeText("https://example.execute-api.ap-northeast-1.amazonaws.com")

        let clientField = app.textFields["クライアントID"]
        clientField.tap()
        clientField.typeText("dummy-client-id")

        let saveButton = app.buttons["この内容で設定する"]
        if !saveButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // Sign-in screen appears once the backend is configured.
        XCTAssertTrue(
            app.textFields["メールアドレス"].waitForExistence(timeout: 10),
            "ログイン画面が表示されること"
        )
        XCTAssertTrue(app.secureTextFields["パスワード(8文字以上)"].exists)
        attachScreenshot(named: "02-sign-in")

        // Switch the segmented control to sign-up mode and capture it too.
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
