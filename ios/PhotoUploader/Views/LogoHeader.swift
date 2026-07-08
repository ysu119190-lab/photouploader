import SwiftUI

/// Brand header shown at the top of the setup and sign-in screens.
struct LogoHeader: View {
    var subtitle: String?

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image("Logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 76)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.30, green: 0.66, blue: 0.97),
                                Color(red: 0.06, green: 0.35, blue: 0.87),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("PhotoUploader")
                    .font(.title3.weight(.bold))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    LogoHeader(subtitle: "写真をあなたのAWSへバックアップ")
}
