import XCTest

/// Captures the five App Store screenshots (notes/store-listing.md §7) by
/// driving the app against the real review-demo backend, so the shots can be
/// produced on CI without a local Mac. Run by the store-screenshots workflow,
/// which opts in via UITEST_STORE_SCREENSHOTS and pre-grants photo access;
/// regular CI runs skip this class.
final class StoreScreenshotUITests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            env["UITEST_STORE_SCREENSHOTS"] == "1",
            "store-screenshots ワークフロー専用(通常CIではスキップ)"
        )
    }

    func testCaptureStoreScreenshots() throws {
        let configJSON = try XCTUnwrap(env["UITEST_CONFIG_JSON"], "デモ環境のAppConfigJsonが必要")
        let demoEmail = try XCTUnwrap(env["UITEST_DEMO_EMAIL"], "審査用アカウントのメールアドレスが必要")
        let demoPassword = try XCTUnwrap(env["UITEST_DEMO_PASSWORD"], "審査用アカウントのパスワードが必要")

        // ① はじめてガイド — fresh install, before any backend is configured.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDisableAds"]
        app.launch()
        let guideEntry = app.staticTexts["はじめての方はこちら(設定ガイド)"]
        XCTAssertTrue(guideEntry.waitForExistence(timeout: 20), "接続先設定画面が表示されること")
        guideEntry.tap()
        sleep(2)
        attachScreenshot(named: "01-first-run-guide")
        app.terminate()

        // Relaunch connected to the demo backend, with the sign-in form
        // prefilled (both wired through DEBUG-only hooks in the app).
        app.launchArguments = ["-uiTestDisableAds"]
        app.launchEnvironment = [
            "UITEST_CONFIG_JSON": configJSON,
            "UITEST_PREFILL_EMAIL": demoEmail,
            "UITEST_PREFILL_PASSWORD": demoPassword,
        ]
        app.launch()
        let loginButton = app.buttons["ログインする"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 20), "ログイン画面が表示されること")
        sleep(1)
        loginButton.tap()

        // ⑤ 保存モードの選択 — the one-time chooser right after first sign-in.
        // Poll for either the chooser or the signed-in tab bar so a missing
        // chooser (already answered / presentation race) doesn't kill the
        // whole capture run; if neither shows up, sign-in itself failed —
        // attach the screen and hierarchy as evidence before failing.
        let storageConfirm = app.buttons["この設定ではじめる"]
        let backupTab = app.tabBars.buttons["バックアップ"]
        let signInDeadline = Date().addingTimeInterval(60)
        while Date() < signInDeadline && !storageConfirm.exists && !backupTab.exists {
            sleep(2)
        }
        if storageConfirm.exists {
            sleep(2)
            attachScreenshot(named: "05-storage-mode-choice")
            storageConfirm.tap()
        } else if !backupTab.exists {
            attachScreenshot(named: "99-signin-failure-screen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "99-signin-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("サインイン後の画面に遷移できなかった(99-signin-failure-* 添付を確認。認証エラーならログイン画面の赤いメッセージに理由が写っている)")
        }

        // ② アップロード進捗 — pick several items in the in-app library
        // picker (photo access is pre-granted via `simctl privacy`).
        let libraryButton = app.buttons["ライブラリから選ぶ(アップ済み表示)"]
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 15))
        libraryButton.tap()

        let assetCells = app.descendants(matching: .any)
            .matching(identifier: "library-asset-cell")
        XCTAssertTrue(
            assetCells.firstMatch.waitForExistence(timeout: 30),
            "ライブラリに写真があること(シミュレータ標準のサンプル写真を想定)"
        )
        sleep(3) // thumbnails
        let selectionCount = min(assetCells.count, 6)
        XCTAssertGreaterThan(selectionCount, 0)
        for index in 0..<selectionCount {
            assetCells.element(boundBy: index).tap()
        }
        app.buttons["アップロード"].tap()

        // The first batch triggers the notification-permission system alert;
        // uploads wait until it is answered, so dismiss it via Springboard.
        allowNotificationAlertIfPresent()

        // Screenshot while the batch is visibly in flight. Small sample
        // photos can finish fast, so don't fail if the moment was missed.
        let uploadingHeader = app.staticTexts["アップロード中"]
        if uploadingHeader.waitForExistence(timeout: 20) {
            attachScreenshot(named: "02-upload-progress")
            sleep(2)
            if uploadingHeader.exists {
                attachScreenshot(named: "02b-upload-progress-later")
            }
        }

        // Wait for the batch summary header that replaces "アップロード中".
        let doneHeader = app.staticTexts["今回のアップロード"]
        XCTAssertTrue(doneHeader.waitForExistence(timeout: 600), "アップロードが完了すること")
        attachScreenshot(named: "02c-upload-finished")

        // ③ 保存済みギャラリー(グリッド)
        app.tabBars.buttons["保存済み"].tap()
        let photoCells = app.descendants(matching: .any)
            .matching(identifier: "gallery-photo-cell")
        XCTAssertTrue(
            photoCells.firstMatch.waitForExistence(timeout: 60),
            "保存済みタブにアップロードした写真が表示されること"
        )
        sleep(10) // let the S3 thumbnails finish loading
        attachScreenshot(named: "03-gallery-grid")

        // ④ 拡大表示+「端末に保存」
        photoCells.firstMatch.tap()
        let saveButton = app.buttons["端末に保存"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 30), "拡大表示が開くこと")
        sleep(8) // full-size image download
        attachScreenshot(named: "04-photo-detail")
    }

    /// Taps "Allow" on the notification-permission alert, which belongs to
    /// Springboard rather than the app. Label depends on the simulator's
    /// system language; nothing to do if the alert never shows.
    private func allowNotificationAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "許可"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 5) {
                button.tap()
                return
            }
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
