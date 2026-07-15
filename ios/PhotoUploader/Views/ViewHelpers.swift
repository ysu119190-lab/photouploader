import SwiftUI

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
