import SwiftUI
import VisionKit

/// Camera sheet that scans the configuration QR code.
struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            QRScannerView(onScan: onScan)
                .ignoresSafeArea()
                .navigationTitle("QRコードを読み取る")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// VisionKit-based QR scanner. Unsupported in the simulator, so callers hide
/// the scan button when `isSupported` is false.
struct QRScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasDelivered = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasDelivered else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    hasDelivered = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}
