import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// White tile with a QR code — scannable in both light and dark mode.
struct QRCodeView: View {
    let content: String

    var body: some View {
        Group {
            if let image = QRCode.image(for: content) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "xmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(KenniGradient.primary.opacity(0.7), lineWidth: 2))
    }
}
