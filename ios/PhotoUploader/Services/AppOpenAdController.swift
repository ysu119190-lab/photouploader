import GoogleMobileAds
import UIKit

/// Shows an app-open ad when the user returns to the app from the
/// background. Cold launches are left alone (the splash and setup flow run
/// there), quick app switches are not interrupted, and everything fails
/// open — the app never waits on an ad.
final class AppOpenAdController: NSObject {
    static let shared = AppOpenAdController()

    /// Google recommends discarding app-open ads not shown within 4 hours.
    private static let maxAdAge: TimeInterval = 4 * 60 * 60
    /// Don't greet the user with a full-screen ad after a brief app switch.
    private static let minBackgroundInterval: TimeInterval = 60

    private var ad: GADAppOpenAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var isPresenting = false
    private var backgroundedAt: Date?

    /// Fetches the next ad in the background.
    func preload() {
        guard !AdsConfig.isDisabledForUITests else { return }
        guard ad == nil, !isLoading else { return }
        isLoading = true
        GADAppOpenAd.load(
            withAdUnitID: AdsConfig.appOpenAdUnitID,
            request: AdsConfig.makeRequest()
        ) { [weak self] ad, _ in
            guard let self else { return }
            self.isLoading = false
            self.ad = ad
            self.loadedAt = Date()
            ad?.fullScreenContentDelegate = self
        }
    }

    func appDidEnterBackground() {
        backgroundedAt = Date()
    }

    /// Call when the scene becomes active again.
    @MainActor
    func presentIfReturningFromBackground() {
        guard !AdsConfig.isDisabledForUITests else { return }
        guard let backgroundedAt,
              Date().timeIntervalSince(backgroundedAt) >= Self.minBackgroundInterval
        else { return }
        self.backgroundedAt = nil

        guard !isPresenting,
              let ad,
              let loadedAt,
              Date().timeIntervalSince(loadedAt) < Self.maxAdAge,
              let root = Self.rootViewController,
              // Never present over another full-screen flow (picker, camera,
              // rewarded ad, detail sheet).
              root.presentedViewController == nil
        else {
            if self.ad == nil {
                preload()
            }
            return
        }

        self.ad = nil
        isPresenting = true
        ad.present(fromRootViewController: root)
    }

    @MainActor
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

extension AppOpenAdController: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        isPresenting = false
        preload()
    }

    func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        isPresenting = false
        preload()
    }
}
