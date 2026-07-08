import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var viewModel = UploadViewModel()
    @State private var selection: [PhotosPickerItem] = []
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
            Group {
                switch session.state {
                case .loading:
                    ProgressView()
                case .needsSetup:
                    SetupView(session: session)
                case .signedOut, .needsConfirmation:
                    AuthView(session: session)
                case .signedIn:
                    TabView {
                        uploadView
                            .tabItem {
                                Label("バックアップ", systemImage: "square.and.arrow.up.on.square")
                            }
                        GalleryView()
                            .tabItem {
                                Label("保存済み", systemImage: "photo.stack")
                            }
                    }
                }
            }

            if isShowingSplash {
                SplashView()
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .task {
            await session.bootstrap()
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) {
                isShowingSplash = false
            }
        }
    }

    private var uploadView: some View {
        NavigationStack {
            List {
                if !viewModel.items.isEmpty {
                    Section {
                        ForEach(viewModel.items) { item in
                            UploadRow(item: item)
                        }
                    } header: {
                        UploadSummaryHeader(
                            done: viewModel.doneCount,
                            skipped: viewModel.skippedCount,
                            failed: viewModel.failedCount,
                            total: viewModel.items.count,
                            isUploading: viewModel.isUploading
                        )
                    }
                }

                if !viewModel.history.isEmpty {
                    Section {
                        ForEach(viewModel.history) { batch in
                            HistoryRow(batch: batch)
                        }
                    } header: {
                        HStack {
                            Text("これまでのアップロード")
                            Spacer()
                            Button("履歴を消去") {
                                viewModel.clearHistory()
                            }
                            .font(.caption)
                        }
                        .textCase(nil)
                    }
                }
            }
            .overlay {
                if viewModel.items.isEmpty && viewModel.history.isEmpty {
                    ContentUnavailableView(
                        "写真がありません",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("右上のボタンから写真を選ぶとS3にアップロードします")
                    )
                }
            }
            .navigationTitle("Photo Uploader")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("ログアウト") {
                        Task { await session.signOut() }
                    }
                    .disabled(viewModel.isUploading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: nil,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("写真を選択", systemImage: "photo.badge.plus")
                    }
                    .disabled(viewModel.isUploading)
                }
            }
            .onChange(of: selection) { _, newValue in
                guard !newValue.isEmpty else { return }
                let picked = newValue
                selection = []
                Task {
                    // Rewarded ad gates the upload; if none is available the
                    // upload starts anyway (backups are never ad-blocked).
                    _ = await RewardedAdController.shared.presentIfReady()
                    await viewModel.handleSelection(picked)
                }
            }
            .safeAreaInset(edge: .bottom) {
                BannerAdView()
                    .frame(width: 320, height: 50)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

/// Batch progress bar shown above the upload list.
private struct UploadSummaryHeader: View {
    let done: Int
    let skipped: Int
    let failed: Int
    let total: Int
    let isUploading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isUploading ? "アップロード中" : "今回のアップロード")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(summaryText)
                    .font(.caption)
                    .monospacedDigit()
            }
            ProgressView(value: Double(done + skipped + failed), total: Double(max(total, 1)))
                .tint(failed > 0 ? .orange : .accentColor)
        }
        .padding(.vertical, 6)
        .textCase(nil)
    }

    private var summaryText: String {
        var text = "完了 \(done)/\(total)"
        if skipped > 0 { text += "・スキップ \(skipped)" }
        if failed > 0 { text += "・失敗 \(failed)" }
        return text
    }
}

/// One row per past upload operation.
private struct HistoryRow: View {
    let batch: UploadBatchSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: batch.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(batch.failed > 0 ? Color.orange : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var summaryText: String {
        var parts = ["\(batch.total)枚中\(batch.done)枚アップロード"]
        if batch.skipped > 0 { parts.append("スキップ\(batch.skipped)") }
        if batch.failed > 0 { parts.append("失敗\(batch.failed)") }
        return parts.joined(separator: "・")
    }
}

private struct UploadRow: View {
    let item: UploadItem

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                statusView
            }
            Spacer()
            statusIcon
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let image = item.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.secondarySystemBackground)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case .pending:
            Text("待機中")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .uploading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        case .done(let key):
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .skipped:
            Text("アップロード済みのためスキップ")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .uploading:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView()
}
