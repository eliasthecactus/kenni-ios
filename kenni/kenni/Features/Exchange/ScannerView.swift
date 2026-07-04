import SwiftUI
import UIKit
import VisionKit
import Vision

/// Camera QR scanner backed by VisionKit. Falls back to a paste field where the
/// camera isn't available (e.g. simulator) — KENNI codes are just text.
struct ScannerView: View {
    let prompt: String
    let onCode: (String) -> Void

    @State private var manualCode = ""

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if scannerAvailable {
                DataScannerRepresentable(onCode: onCode)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(KenniGradient.cool.opacity(0.7), lineWidth: 2))
                    .frame(maxHeight: 340)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.on.rectangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(L("No camera here. Ask them to tap \"Copy my code\" or \"Share my link\" on their My code screen, then paste it here."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    TextField(L("KENNI code or link"), text: $manualCode, axis: .vertical)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(3)
                        .padding(10)
                        .background(Color.kenniBackground.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(L("Use code")) {
                        onCode(manualCode.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .buttonStyle(KenniSecondaryButtonStyle())
                    .disabled(manualCode.isEmpty)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.kenniCard, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in added {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    delivered = true
                    onCode(value)
                    return
                }
            }
        }
    }
}
