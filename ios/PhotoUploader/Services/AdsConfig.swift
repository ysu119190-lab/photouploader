import Foundation

/// AdMob configuration.
///
/// The current values are Google's official TEST IDs — they always serve
/// sample ads and generate no revenue. Before releasing to the App Store:
/// 1. Create an AdMob account and register the app
/// 2. Replace `GADApplicationIdentifier` in project.yml with your app ID
/// 3. Replace `bannerAdUnitID` below with your banner ad unit ID
enum AdsConfig {
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
}
