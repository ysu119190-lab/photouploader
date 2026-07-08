import SwiftUI

/// Animated launch overlay: the logo springs in on the brand gradient, then
/// the whole view is faded out by ContentView.
struct SplashView: View {
    @State private var isVisible = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.77, blue: 0.98),
                    Color(red: 0.06, green: 0.35, blue: 0.87),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("Logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .foregroundStyle(.white)

                Text("PhotoUploader")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("写真をあなたのAWSへバックアップ")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .scaleEffect(isVisible ? 1 : 0.7)
            .opacity(isVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

#Preview {
    SplashView()
}
