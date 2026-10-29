import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Encodes the same short-lived payload as manual pairing, entirely on this Mac.
enum PairingQRCode {
    static func image(for code: String) -> CGImage? {
        guard !code.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Integer scaling preserves sharp modules. The view adds a white quiet zone.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}

struct PairingQRCodeView: View {
    let code: String

    var body: some View {
        if let image = PairingQRCode.image(for: code) {
            Image(image, scale: 1, label: Text("Pairing QR code"))
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 164, height: 164)
                .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHint("Scan with Phone Check on Android, or use Copy code.")
        } else {
            Text("QR code unavailable. Copy the code instead.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
