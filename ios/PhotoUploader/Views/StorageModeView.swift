import SwiftUI

/// Lets the user choose how uploaded photos are stored in S3, with the cost
/// and trade-offs of each mode spelled out. The choice applies to photos
/// uploaded afterwards; previously uploaded photos are unaffected.
struct StorageModeView: View {
    @AppStorage("storage-mode") private var rawMode = StorageMode.standard.rawValue

    var body: some View {
        List {
            Section {
                Text("写真の保存方法を選べます。いつでも変更でき、変更後にアップロードする写真に適用されます(すでにアップロード済みの写真はそのままです)。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(StorageMode.allCases) { mode in
                Section {
                    Button {
                        rawMode = mode.rawValue
                    } label: {
                        modeRow(mode)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if mode == .saver {
                        Text("「バックアップとして預けておき、めったに見返さない」使い方なら、節約モードが断然おすすめです。")
                    }
                }
            }

            Section("料金の目安について") {
                Text("いずれも東京リージョンでの概算です。実際の料金は保存量・通信量・AWSの料金改定・為替により変動します。料金は写真の枚数ではなく合計サイズで決まります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("保存モード")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func modeRow(_ mode: StorageMode) -> some View {
        let isSelected = rawMode == mode.rawValue
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.headline)
                    Text(mode.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }

            Text(mode.monthlyCostPer100GB)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(mode.details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 6) {
                        Text("・")
                        Text(detail)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        StorageModeView()
    }
}
