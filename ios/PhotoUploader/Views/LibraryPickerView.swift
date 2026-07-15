import Photos
import SwiftUI

/// In-app photo library picker. Unlike the system PhotosPicker it can show
/// which items are already backed up (green badge), sort oldest/newest, and
/// filter to not-yet-uploaded items only.
struct LibraryPickerView: View {
    /// Called with the chosen assets after the sheet dismisses itself.
    let onPick: ([PHAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var assets: [PHAsset] = []
    @State private var selectedIDs: Set<String> = []
    @State private var newestFirst = true
    @State private var showOnlyNew = false

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 2)]

    private var displayedAssets: [PHAsset] {
        guard showOnlyNew else { return assets }
        return assets.filter { !UploadedAssetsStore.contains($0.localIdentifier) }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .notDetermined:
                    ProgressView()
                case .authorized, .limited:
                    pickerContent
                default:
                    deniedView
                }
            }
            .navigationTitle(
                selectedIDs.isEmpty ? "ライブラリから選ぶ" : "\(selectedIDs.count)件を選択中"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("アップロード") {
                        let picked = assets.filter { selectedIDs.contains($0.localIdentifier) }
                        dismiss()
                        onPick(picked)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .task { await requestAndLoad() }
        }
    }

    private var pickerContent: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("並び順", selection: $newestFirst) {
                    Text("新しい順").tag(true)
                    Text("古い順").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Toggle("未アップのみ", isOn: $showOnlyNew)
                    .toggleStyle(.button)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(displayedAssets, id: \.localIdentifier) { asset in
                        AssetCell(
                            asset: asset,
                            isSelected: selectedIDs.contains(asset.localIdentifier),
                            isUploaded: UploadedAssetsStore.contains(asset.localIdentifier)
                        )
                        .onTapGesture { toggle(asset) }
                    }
                }
            }
            .overlay {
                if displayedAssets.isEmpty {
                    ContentUnavailableView(
                        showOnlyNew ? "未アップロードの項目はありません" : "写真がありません",
                        systemImage: "checkmark.circle"
                    )
                }
            }
        }
        .onChange(of: newestFirst) { _, _ in
            loadAssets()
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("写真へのアクセスが必要です", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("アップロード済みマーク付きで写真を選ぶには、写真ライブラリへのアクセスを許可してください")
        } actions: {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func requestAndLoad() async {
        authStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if authStatus == .authorized || authStatus == .limited {
            loadAssets()
        }
    }

    private func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: !newestFirst)
        ]
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image || asset.mediaType == .video {
                list.append(asset)
            }
        }
        assets = list
    }
}

/// One selectable thumbnail with an "already uploaded" badge and, for
/// videos, a duration label.
private struct AssetCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let isUploaded: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay(alignment: .topLeading) {
                if isUploaded {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Self.durationText(asset.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
            }
            .selectableCell(isSelected: isSelected)
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                thumbnail = await Self.loadThumbnail(for: asset)
            }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            // highQualityFormat guarantees the handler runs exactly once,
            // which the continuation requires.
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 180, height: 180),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

#Preview {
    LibraryPickerView { _ in }
}
