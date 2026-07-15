import GoogleMobileAds
import SwiftUI

/// Receives the callback iOS sends when it relaunches (or wakes) the app
/// because background uploads finished.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        GADMobileAds.sharedInstance().start { _ in
            RewardedAdController.shared.preload()
            AppOpenAdController.shared.preload()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploadManager.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundUploadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

@main
struct PhotoUploaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Recreate the background session immediately on launch so tasks that
        // finished while the app was gone get their delegate callbacks.
        _ = BackgroundUploadManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // App-open ad: shown only when coming back from the background
            // (never over a cold launch's splash/setup flow).
            switch phase {
            case .background:
                AppOpenAdController.shared.appDidEnterBackground()
            case .active:
                AppOpenAdController.shared.presentIfReturningFromBackground()
            default:
                break
            }
        }
    }
}
