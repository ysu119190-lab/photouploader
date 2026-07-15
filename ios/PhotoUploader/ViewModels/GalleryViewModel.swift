import SwiftUI

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var photos: [RemotePhoto] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Every album that exists in the user's uploads (for the filter menu).
    @Published private(set) var albums: [String] = []
    /// nil = show everything.
    @Published private(set) var selectedAlbum: String?

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
            let response = try await GalleryClient.fetchPhotos(
                offset: 0,
                album: selectedAlbum
            )
            photos = response.photos
            total = response.total
            nextOffset = response.nextOffset
            albums = response.albums ?? []
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
            let response = try await GalleryClient.fetchPhotos(
                offset: offset,
                album: selectedAlbum
            )
            photos.append(contentsOf: response.photos)
            total = response.total
            nextOffset = response.nextOffset
            albums = response.albums ?? albums
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectAlbum(_ album: String?) async {
        guard album != selectedAlbum else { return }
        selectedAlbum = album
        photos = []
        await refresh()
    }

    /// Moves the given items to the server-side trash and drops them from
    /// the list. Throws so the view can show the error next to the action.
    func deletePhotos(keys: Set<String>) async throws {
        guard !keys.isEmpty else { return }
        try await GalleryClient.deletePhotos(keys: Array(keys))
        photos.removeAll { keys.contains($0.key) }
        total = max(total - keys.count, 0)
    }
}
