import SwiftUI

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var photos: [RemotePhoto] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var nextOffset: Int?
    private var hasLoadedOnce = false

    var canLoadMore: Bool { nextOffset != nil }

    /// Initial load; no-op when already loaded (call refresh() to reload).
    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await GalleryClient.fetchPhotos(offset: 0)
            photos = response.photos
            total = response.total
            nextOffset = response.nextOffset
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, let offset = nextOffset else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await GalleryClient.fetchPhotos(offset: offset)
            photos.append(contentsOf: response.photos)
            total = response.total
            nextOffset = response.nextOffset
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
