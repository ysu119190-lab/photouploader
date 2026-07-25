import SwiftUI
import UIKit

/// A prepared file ready to hand to the share sheet. Identifiable so it can
/// drive `sheet(item:)` once the download finishes.
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin wrapper around `UIActivityViewController` (the system share sheet),
/// which SwiftUI has no native equivalent of for arbitrary file URLs.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension Binding where Value == Bool {
    /// Presence binding for `alert(isPresented:)` driven by an optional
    /// message: true while the source is non-nil, resets it on dismiss.
    init<Wrapped>(isPresent source: Binding<Wrapped?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}

extension View {
    /// Selection chrome shared by the gallery and library-picker grid cells:
    /// accent border + tint wash + top-trailing checkmark.
    @ViewBuilder
    func selectableCell(isSelected: Bool) -> some View {
        overlay {
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.25))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(4)
            }
        }
    }
}
