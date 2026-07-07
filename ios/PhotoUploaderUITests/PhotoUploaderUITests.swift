import XCTest

/// Smoke tests that drive the app in the simulator and attach screenshots,
/// so CI can verify (and show) the UI without a local Mac.
final class PhotoUploaderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsSignInScreen() throws {
        let app = XCUIApplication()
        app.launch()

        // A fresh simulator has no stored session, so the auth screen appears.
        XCTAssertTrue(
            app.textFields["メールアドレス"].waitForExistence(timeout: 10),
            "メールアドレス入力欄が表示されること"
        )
        XCTAssertTrue(
            app.secureTextFields["パスワード(8文字以上)"].exists,
            "パスワード入力欄が表示されること"
        )
        XCTAssertTrue(app.buttons["ログインする"].exists, "ログインボタンが表示されること")

        attachScreenshot(named: "01-sign-in")

        // Switch the segmented control to sign-up mode and capture it too.
        let signUpSegment = app.segmentedControls.buttons["新規登録"]
        if signUpSegment.waitForExistence(timeout: 5) {
            signUpSegment.tap()
            XCTAssertTrue(app.buttons["登録する"].waitForExistence(timeout: 5))
            attachScreenshot(named: "02-sign-up")
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
