import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var viewModel = UploadViewModel()
    @State private var selection: [PhotosPickerItem] = []
    @State private var isShowingSplash = true
    @State private var isConfirmingAccountDeletion = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
    @State private var isShowingLibraryPicker = false
    @State private var isShowingCamera = false

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
                if !viewModel.isUploading {
                    Section {
                        Button {
                            startDifferentialBackup()
                        } label: {
                            Label("新着をまとめてバックアップ", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            isShowingLibraryPicker = true
                        } label: {
                            Label("ライブラリから選ぶ(アップ済み表示)", systemImage: "photo.stack")
                        }
                        if CameraCaptureView.isCameraAvailable {
                            Button {
                                isShowingCamera = true
                            } label: {
                                Label("カメラで撮ってバックアップ", systemImage: "camera")
                            }
                        }
                    } footer: {
                        Text("「新着をまとめてバックアップ」は、まだバックアップしていない写真・動画を自動で探してアップロードします。アルバム分けも保存先に反映されます(初回は写真へのアクセス許可が必要)")
                    }
                }

                if !viewModel.items.isEmpty {
                    Section {
                        ForEach(viewModel.items) { item in
                            UploadRow(item: item)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 8) {
                            UploadSummaryHeader(
                                done: viewModel.doneCount,
                                skipped: viewModel.skippedCount,
                                failed: viewModel.failedCount,
                                total: viewModel.items.count,
                                isUploading: viewModel.isUploading
                            )
                            if !viewModel.isUploading && viewModel.hasRetryableFailures {
                                Button {
                                    Task { await viewModel.retryFailedItems() }
                                } label: {
                                    Label("失敗した項目を再試行", systemImage: "arrow.clockwise")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.borderless)
                                .textCase(nil)
                            }
                        }
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
            .alert(
                "バックアップ",
                isPresented: Binding(
                    get: { viewModel.infoMessage != nil },
                    set: { if !$0 { viewModel.infoMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.infoMessage ?? "")
            }
            .navigationTitle("Photo Uploader")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("アカウント") {
                        Button("ログアウト") {
                            Task { await session.signOut() }
                        }
                        Button("アカウントを削除", role: .destructive) {
                            isConfirmingAccountDeletion = true
                        }
                    }
                    .disabled(viewModel.isUploading || isDeletingAccount)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        StorageModeView()
                    } label: {
                        Label("保存モード", systemImage: "gearshape")
                    }
                    .disabled(viewModel.isUploading)

                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: nil,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        Label("写真・動画を選択", systemImage: "photo.badge.plus")
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
            .sheet(isPresented: $isShowingLibraryPicker) {
                LibraryPickerView { assets in
                    Task {
                        // Same ad gate as the system picker; the controller
                        // waits for the sheet dismissal to finish first.
                        _ = await RewardedAdController.shared.presentIfReady()
                        await viewModel.handleAssets(assets)
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    Task {
                        await viewModel.handleCapturedImage(image)
                    }
                }
                .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                BannerAdView()
                    .frame(width: 320, height: 50)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .confirmationDialog(
                "アカウントを削除しますか?",
                isPresented: $isConfirmingAccountDeletion,
                titleVisibility: .visible
            ) {
                Button("アカウントを完全に削除する", role: .destructive) {
                    deleteAccount()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("ログイン用アカウント(メールアドレス登録)を完全に削除します。この操作は取り消せません。S3にバックアップ済みの写真は削除されず、あなたのAWS環境にそのまま残ります。")
            }
            .alert(
                "アカウントを削除できませんでした",
                isPresented: Binding(
                    get: { accountDeletionError != nil },
                    set: { if !$0 { accountDeletionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(accountDeletionError ?? "")
            }
        }
    }

    private func startDifferentialBackup() {
        Task {
            // The rewarded ad only plays when the scan actually found
            // something to upload (never for an empty diff).
            await viewModel.backupNewItems {
                _ = await RewardedAdController.shared.presentIfReady()
            }
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task { @MainActor in
            defer { isDeletingAccount = false }
            do {
                try await session.deleteAccount()
                // The store was cleared; reset the in-memory list too so a
                // future account on this device starts with an empty screen.
                viewModel.clearHistory()
            } catch {
                accountDeletionError = error.localizedDescription
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
        var parts = ["\(batch.total)件中\(batch.done)件アップロード"]
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
        case .interrupted:
            Text("アプリ再起動により中断(転送は完了している場合があります。「保存済み」タブで確認できます)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        case .interrupted:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
