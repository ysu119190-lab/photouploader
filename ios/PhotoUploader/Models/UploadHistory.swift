import Foundation

/// One finished upload operation (batch), shown in the history list.
struct UploadBatchSummary: Codable, Identifiable {
    let id: UUID
    let date: Date
    let total: Int
    let done: Int
    let skipped: Int
    let failed: Int
}

/// Persists batch summaries across launches (newest first).
enum UploadHistoryStore {
    private static let key = "upload-history"
    private static let maxEntries = 100

    static func load() -> [UploadBatchSummary] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([UploadBatchSummary].self, from: data)
        else {
            return []
        }
        return list
    }

    static func append(_ summary: UploadBatchSummary) {
        var list = load()
        list.insert(summary, at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Remembers which photo-library assets were already uploaded, so re-selected
/// photos are skipped instead of being backed up twice.
///
/// Lookups happen per grid cell per render in the library picker and per
/// asset in the differential-backup scan, so the set lives in memory;
/// UserDefaults is only touched on mutation and first load.
@MainActor
enum UploadedAssetsStore {
    private static let key = "uploaded-asset-ids"

    private static var cache: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: key) ?? []
    )

    static func contains(_ id: String) -> Bool {
        cache.contains(id)
    }

    static func insert(_ id: String) {
        guard cache.insert(id).inserted else { return }
        UserDefaults.standard.set(Array(cache), forKey: key)
    }

    static func clear() {
        cache = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}
