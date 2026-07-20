import AVKit
import SwiftUI

/// Grid of the user's uploaded photos and videos, loaded from S3 via
/// presigned URLs. Supports album filtering and moving items to the
/// server-side trash.
struct GalleryView: View {
    @StateObject private var viewModel = GalleryViewModel()
    @State private var selectedPhoto: RemotePhoto?
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.photos) { photo in
                        GalleryCell(
                            photo: photo,
                            isSelected: selectedKeys.contains(photo.key)
                        )
                        .onTapGesture {
                            if isSelecting {
                                toggleSelection(photo)
                            } else {
                                selectedPhoto = photo
                            }
                        }
                        .onAppear {
                            if photo.id == viewModel.photos.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                        .accessibilityElement()
                        .accessibilityIdentifier(
                            photo.isVideo ? "gallery-video-cell" : "gallery-photo-cell"
                        )
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    albumMenu
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            if isDeleting {
                                ProgressView()
                            } else {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        .disabled(selectedKeys.isEmpty || isDeleting)

                        Button("完了") {
                            isSelecting = false
                            selectedKeys = []
                        }
                    } else {
                        Button("選択") {
                            isSelecting = true
                        }
                        .disabled(viewModel.photos.isEmpty)
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadIfNeeded()
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
            .confirmationDialog(
                "\(selectedKeys.count)件をゴミ箱へ移動しますか?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("ゴミ箱へ移動する", role: .destructive) {
                    deleteSelection()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("移動した写真・動画は30日後に完全に削除されます(それまではS3の trash/ フォルダに残ります)。端末内の写真は削除されません。")
            }
        }
    }

    private var navigationTitle: String {
        if isSelecting {
            return selectedKeys.isEmpty ? "選択してください" : "\(selectedKeys.count)件を選択中"
        }
        let base = viewModel.selectedAlbum ?? "保存済み"
        return viewModel.total > 0 ? "\(base) (\(viewModel.total)件)" : base
    }

    private var albumMenu: some View {
        Menu {
            Button {
                Task { await viewModel.selectAlbum(nil) }
            } label: {
                if viewModel.selectedAlbum == nil {
                    Label("すべて", systemImage: "checkmark")
                } else {
                    Text("すべて")
                }
            }
            ForEach(viewModel.albums, id: \.self) { album in
                Button {
                    Task { await viewModel.selectAlbum(album) }
                } label: {
                    if viewModel.selectedAlbum == album {
                        Label(album, systemImage: "checkmark")
                    } else {
                        Text(album)
                    }
                }
            }
        } label: {
            Label("アルバム", systemImage: "folder")
        }
        .disabled(viewModel.albums.isEmpty)
    }

    private func toggleSelection(_ photo: RemotePhoto) {
        if selectedKeys.contains(photo.key) {
            selectedKeys.remove(photo.key)
        } else {
            selectedKeys.insert(photo.key)
        }
    }

    private func deleteSelection() {
        isDeleting = true
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try await viewModel.deletePhotos(keys: selectedKeys)
                selectedKeys = []
                isSelecting = false
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

/// One thumbnail in the grid. Prefers the cheap server-side thumbnail;
/// videos without one show a placeholder tile.
private struct GalleryCell: View {
    let photo: RemotePhoto
    var isSelected = false

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if photo.isVideo && photo.thumbnailURL == nil {
                    VStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                        Text("動画")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                } else if let url = photo.isVideo ? photo.thumbnailURL : photo.gridImageURL {
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
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo && photo.thumbnailURL != nil {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(4)
                }
            }
            .selectableCell(isSelected: isSelected)
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
                isPresented: Binding(isPresent: $saveResult)
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
