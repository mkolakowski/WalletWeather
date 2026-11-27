import AVFoundation
import SwiftUI
import VisionKit
import WalletWeatherKit

/// Scan the QR code the web app's Settings → API tokens draws beside a new
/// token (ios-app phase 7, #100). It holds the same `walletweather://connect`
/// link as the Open in WalletWeather button, so a code goes to the same "Connect
/// to …?" question. The camera is asked for only here, when this opens.
struct QRScanSheet: View {
    /// A WalletWeather link was scanned; the sheet closes itself.
    let onLink: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var access = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan a QR code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if !DataScannerViewController.isSupported {
            ContentUnavailableView {
                Label("Can't scan here", systemImage: "qrcode.viewfinder")
            } description: {
                Text("This iPhone's camera can't scan QR codes in the app. Point the Camera app at the code instead, or paste the token.")
            }
        } else {
            switch access {
            case .authorized:
                ZStack(alignment: .bottom) {
                    QRScanner(onCode: scanned)
                        .ignoresSafeArea(edges: .bottom)
                    Text(problem ?? "Point the camera at the QR code in the web app's Settings → API tokens.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.bar))
                        .padding(20)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            case .notDetermined:
                ProgressView()
                    .task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        access = AVCaptureDevice.authorizationStatus(for: .video)
                    }
            default:
                ContentUnavailableView {
                    Label("The camera is off for WalletWeather", systemImage: "camera.fill")
                } description: {
                    Text("Allow the camera in Settings to scan a QR code, or point the Camera app at the code instead.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .prominentButton()
                }
            }
        }
    }

    private func scanned(_ text: String) {
        guard let url = URL(string: text), case .connect = AppLink(url) else {
            problem = "That QR code isn't a WalletWeather sign-in. In the web app, make a token in Settings → API tokens and choose Show QR code."
            return
        }
        dismiss()
        onLink(url)
    }
}

/// The system's scanner (VisionKit), looking for QR codes only.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        /// Each code is handled once, not on every frame it stays in view.
        private var seen: Set<String> = []

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case let .barcode(code) = item, let text = code.payloadStringValue,
                      seen.insert(text).inserted else { continue }
                onCode(text)
            }
        }
    }
}
