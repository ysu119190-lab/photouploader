import SwiftUI

/// One photo the user picked, tracked through its upload lifecycle.
struct UploadItem: Identifiable {
    enum Status {
        case pending
        case uploading(progress: Double)
        case done(key: String)
        /// Already uploaded in a previous batch — not sent again.
        case skipped
        case failed(message: String)
        /// Restored after a relaunch while this item was still in flight.
        /// The background transfer may well have finished — the app just
        /// lost the callback that would have told it so.
        case interrupted
    }

    let id = UUID()
    let displayName: String
    var thumbnail: UIImage?
    var status: Status = .pending
}

/// Codable snapshot of one list row, so the progress list survives a
/// relaunch (thumbnails are intentionally dropped — too heavy to persist).
struct PersistedUploadItem: Codable {
    enum Kind: String, Codable {
        case pending, uploading, done, skipped, failed, interrupted
    }

    let displayName: String
    let kind: Kind
    /// Object key for done items, error message for failed ones.
    let detail: String?
}

extension UploadItem {
    var persisted: PersistedUploadItem {
        let kind: PersistedUploadItem.Kind
        var detail: String?
        switch status {
        case .pending:
            kind = .pending
        case .uploading:
            kind = .uploading
        case .done(let key):
            kind = .done
            detail = key
        case .skipped:
            kind = .skipped
        case .failed(let message):
            kind = .failed
            detail = message
        case .interrupted:
            kind = .interrupted
        }
        return PersistedUploadItem(displayName: displayName, kind: kind, detail: detail)
    }

    /// Rebuilds a row from a snapshot. Anything that was still in flight
    /// when the app died comes back as `.interrupted`.
    init(restoring persisted: PersistedUploadItem) {
        self.displayName = persisted.displayName
        switch persisted.kind {
        case .done:
            self.status = .done(key: persisted.detail ?? "")
        case .skipped:
            self.status = .skipped
        case .failed:
            self.status = .failed(message: persisted.detail ?? "失敗しました")
        case .pending, .uploading, .interrupted:
            self.status = .interrupted
        }
    }
}

/// Persists the current batch's rows across launches.
enum UploadItemsSnapshotStore {
    private static let key = "upload-items-snapshot"

    static func load() -> [PersistedUploadItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([PersistedUploadItem].self, from: data)
        else {
            return []
        }
        return list
    }

    static func save(_ items: [PersistedUploadItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
