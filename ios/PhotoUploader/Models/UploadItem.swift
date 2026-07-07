import SwiftUI

/// One photo the user picked, tracked through its upload lifecycle.
struct UploadItem: Identifiable {
    enum Status {
        case pending
        case uploading(progress: Double)
        case done(key: String)
        case failed(message: String)
    }

    let id = UUID()
    let displayName: String
    var thumbnail: UIImage?
    var status: Status = .pending
}
