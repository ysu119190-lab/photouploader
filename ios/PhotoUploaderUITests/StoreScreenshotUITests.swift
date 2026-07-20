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
        // Detect the sheet by its nav-bar title: the confirm button sits at
        // the bottom of a long lazy List and does not exist in the hierarchy
        // until scrolled to (run #3 proved this — the sheet covered the
        // screen while the button query stayed empty). The tab bar behind
        // the sheet still "exists", so it can't disprove the sheet either.
        let storageSheetTitle = app.staticTexts["保存モードの選択"]
        let backupTab = app.tabBars.buttons["バックアップ"]
        let signInDeadline = Date().addingTimeInterval(60)
        while Date() < signInDeadline && !storageSheetTitle.exists && !backupTab.exists {
            sleep(2)
        }
        // The sheet animates in an instant after the tab view appears, so
        // even when the tab bar wins the race, give the sheet time to show.
        if !storageSheetTitle.exists {
            _ = storageSheetTitle.waitForExistence(timeout: 10)
        }
        if storageSheetTitle.exists {
            sleep(2)
            attachScreenshot(named: "05-storage-mode-choice")
            // Scroll until the lazily-created confirm button materializes.
            let storageConfirm = app.buttons["この設定ではじめる"]
            var swipes = 0
            while !storageConfirm.exists && swipes < 8 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(storageConfirm.exists, "保存モード選択の確定ボタンまでスクロールできること")
            storageConfirm.tap()
            sleep(2) // let the sheet finish dismissing before tapping below it
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

        // The workflow pre-grants photo access, but if the grant didn't take
        // effect the system permission dialog appears here — answer it.
        tapSpringboardAlertButton(
            ["Allow Full Access", "Allow Access to All Photos",
             "フルアクセスを許可", "すべての写真へのアクセスを許可"],
            timeout: 5
        )

        let assetCells = app.descendants(matching: .any)
            .matching(identifier: "library-asset-cell")
        if !assetCells.firstMatch.waitForExistence(timeout: 30) {
            attachScreenshot(named: "99-picker-failure-screen")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "99-picker-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("ライブラリに写真が表示されなかった(99-picker-failure-* 添付を確認。権限拒否画面か空ライブラリかが写っている)")
            return
        }
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
        tapSpringboardAlertButton(["Allow", "許可"], timeout: 5)
    }

    /// Polls Springboard for an alert button with any of the given labels
    /// (system dialogs live outside the app process) and taps the first
    /// match. Returns false if none appeared before the timeout.
    @discardableResult
    private func tapSpringboardAlertButton(_ labels: [String], timeout: TimeInterval) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            sleep(1)
        } while Date() < deadline
        return false
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
