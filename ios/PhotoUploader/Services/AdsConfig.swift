import GoogleMobileAds

/// AdMob configuration.
///
/// Release builds use the production ad units; Debug builds (and therefore
/// CI's simulator tests) use Google's official test IDs — tapping real ads
/// during development counts as invalid traffic and can get the AdMob
/// account suspended. The production app ID lives in project.yml
/// (GADApplicationIdentifier); test unit IDs work fine under it.
enum AdsConfig {
    #if DEBUG
    static let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"
    static let appOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    #else
    static let bannerAdUnitID = "ca-app-pub-5308803840858138/8351779648"
    static let rewardedAdUnitID = "ca-app-pub-5308803840858138/1031572681"
    static let appOpenAdUnitID = "ca-app-pub-5308803840858138/1658378785"
    #endif

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
