import GoogleMobileAds
import UIKit

/// Loads and presents rewarded ads. The upload flow shows one before a batch
/// starts; if no ad is ready (offline, no fill), the upload proceeds anyway
/// so backups are never blocked by ad availability.
final class RewardedAdController: NSObject {
    static let shared = RewardedAdController()

    private var rewardedAd: GADRewardedAd?
    private var isLoading = false
    private var dismissContinuation: CheckedContinuation<Void, Never>?
    private var didEarnReward = false

    /// Fetches the next ad in the background.
    func preload() {
        guard !AdsConfig.isDisabledForUITests else { return }
        guard rewardedAd == nil, !isLoading else { return }
        isLoading = true
        GADRewardedAd.load(
            withAdUnitID: AdsConfig.rewardedAdUnitID,
            request: AdsConfig.makeRequest()
        ) { [weak self] ad, _ in
            guard let self else { return }
            self.isLoading = false
            self.rewardedAd = ad
            ad?.fullScreenContentDelegate = self
        }
    }

    /// Presents a rewarded ad if one is ready and waits until it is closed.
    /// Returns true when the user earned the reward (finished watching).
    @MainActor
    func presentIfReady() async -> Bool {
        guard !AdsConfig.isDisabledForUITests else { return false }
        guard rewardedAd != nil, let root = Self.rootViewController else {
            preload()
            return false
        }

        // The photo picker sheet is usually still animating closed when the
        // upload flow reaches this point, and UIKit refuses to present a
        // full-screen ad over an in-flight dismissal. Wait until nothing is
        // presented (up to a few seconds) before showing the ad.
        var waitedSeconds = 0.0
        while root.presentedViewController != nil, waitedSeconds < 3.0 {
            try? await Task.sleep(for: .milliseconds(200))
            waitedSeconds += 0.2
        }

        guard let ad = rewardedAd else { return false }
        rewardedAd = nil
        didEarnReward = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            dismissContinuation = continuation
            ad.present(fromRootViewController: root) { [weak self] in
                self?.didEarnReward = true
            }
        }

        preload()
        return didEarnReward
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

extension RewardedAdController: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        dismissContinuation?.resume()
        dismissContinuation = nil
    }

    func ad(
        _ ad: GADFullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        dismissContinuation?.resume()
        dismissContinuation = nil
    }
}
