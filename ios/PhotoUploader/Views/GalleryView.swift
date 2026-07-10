import AVKit
import SwiftUI

/// Grid of the user's uploaded photos and videos, loaded from S3 via
/// presigned URLs.
struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @State private var selectedPhoto: RemotePhoto?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.photos) { photo in
                        GalleryCell(photo: photo)
                            .onTapGesture {
                                selectedPhoto = photo
                            }
                            .onAppear {
                                if photo.id == viewModel.photos.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .overlay {
                if viewModel.photos.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                    ContentUnavailableView(
                        "保存済みの写真がありません",
                        systemImage: "photo.stack",
                        description: Text("「バックアップ」タブから写真や動画をアップロードすると、ここに表示されます")
                    )
                }
            }
            .navigationTitle("保存済み \(viewModel.total > 0 ? "(\(viewModel.total)件)" : "")")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
        }
    }
}

/// One thumbnail in the grid. Videos show a placeholder tile (generating
/// remote video thumbnails per cell would be slow and costly).
private struct GalleryCell: View {
    let photo: RemotePhoto

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photo.isVideo {
                    VStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                        Text("動画")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } else if let url = photo.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Full-screen viewer for one photo or video, with a "save back to the
/// device" (restore) action.
private struct PhotoDetailView: View {
    let photo: RemotePhoto
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveResult: String?

    var body: some View {
        NavigationStack {
            Group {
                if photo.isVideo {
                    if let url = photo.imageURL {
                        VideoPlayer(player: AVPlayer(url: url))
                    }
                } else if let url = photo.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            ContentUnavailableView(
                                "読み込めませんでした",
                                systemImage: "exclamationmark.triangle"
                            )
                        default:
                            ProgressView()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveToLibrary()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("端末に保存", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert(
                "端末への保存",
                isPresented: Binding(
                    get: { saveResult != nil },
                    set: { if !$0 { saveResult = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveResult ?? "")
            }
        }
    }

    private var detailTitle: String {
        guard let date = photo.uploadedAt else { return photo.isVideo ? "動画" : "写真" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func saveToLibrary() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await MediaSaver.saveToPhotoLibrary(photo)
                saveResult = "写真アプリに保存しました"
            } catch {
                saveResult = error.localizedDescription
            }
        }
    }
}

#Preview {
    GalleryView()
}
