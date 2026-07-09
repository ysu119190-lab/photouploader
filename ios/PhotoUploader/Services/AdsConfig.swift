import GoogleMobileAds

/// AdMob configuration.
///
/// The current values are Google's official TEST IDs — they always serve
/// sample ads and generate no revenue. Before releasing to the App Store:
/// 1. Create an AdMob account and register the app
/// 2. Replace `GADApplicationIdentifier` in project.yml with your app ID
/// 3. Replace `bannerAdUnitID` below with your banner ad unit ID
enum AdsConfig {
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    /// Every ad request must be created here. Requests carry npa=1 so Google
    /// only serves non-personalized ads — the App Privacy label declares "no
    /// tracking" and the app needs no ATT prompt, which is only true while
    /// all requests stay non-personalized. Keep the AdMob console's consent
    /// settings aligned with this (see notes/app-privacy-label.md).
    static func makeRequest() -> GADRequest {
        let request = GADRequest()
        let extras = GADExtras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }
}
