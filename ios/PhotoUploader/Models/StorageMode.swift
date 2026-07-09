import Foundation

/// Where uploaded photos are stored in S3. Chosen by the user in the app;
/// sent to the backend as the requested S3 storage class.
enum StorageMode: String, CaseIterable, Identifiable {
    /// S3 Standard — instant viewing, higher storage cost. For people who
    /// look back at their photos often.
    case standard = "STANDARD"
    /// S3 Glacier Instant Retrieval — much cheaper storage, still instant to
    /// view, but a small per-view retrieval fee. For seldom-viewed backups.
    case saver = "GLACIER_IR"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "標準モード"
        case .saver: return "節約モード"
        }
    }

    var shortLabel: String {
        switch self {
        case .standard: return "標準"
        case .saver: return "節約"
        }
    }

    var tagline: String {
        switch self {
        case .standard: return "よく見返す人向け"
        case .saver: return "あまり見返さない人向け"
        }
    }

    /// Rough monthly storage cost per 100GB (Tokyo region, approximate).
    var monthlyCostPer100GB: String {
        switch self {
        case .standard: return "約375〜400円/月(100GBあたり)"
        case .saver: return "約75円/月(100GBあたり)"
        }
    }

    var details: [String] {
        switch self {
        case .standard:
            return [
                "写真をすぐに表示できます",
                "「保存済み」タブでの閲覧に追加料金はかかりません",
                "保存料は節約モードより高めです",
            ]
        case .saver:
            return [
                "保存料が標準モードの約1/5になります",
                "写真の表示は標準モードと同じく一瞬です",
                "写真を表示(取り出す)たびにごく少額の料金がかかります(約0.03ドル/GB)",
                "最低90日分の保存料が目安としてかかります(バックアップ用途では問題になりにくい設計です)",
            ]
        }
    }
}

enum StorageModeStore {
    private static let key = "storage-mode"

    static var current: StorageMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let mode = StorageMode(rawValue: raw)
            else {
                return .standard
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
