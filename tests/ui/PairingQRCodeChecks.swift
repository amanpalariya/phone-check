import AppKit
import SwiftUI
import Vision

/// Decode the actual SwiftUI surface, including its quiet zone, in both appearances.
@main
struct PairingQRCodeChecks {
    @MainActor
    static func main() throws {
        precondition(PairingQRCode.image(for: "") == nil)
        let secret = Data((0..<32).map(UInt8.init)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        for host in ["10.0.0.1", "192.168.100.254", "172.31.255.254"] {
            let code = "pc1|\(host)|47831|\(secret)"
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: PairingQRCodeView(code: code)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let image = renderer.cgImage else { fatalError("QR view did not render") }
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                try VNImageRequestHandler(cgImage: image).perform([request])
                precondition(request.results?.count == 1)
                precondition(request.results?.first?.payloadStringValue == code,
                             "Rendered QR did not preserve the pairing payload")
            }
        }
        print("Pairing QR checks passed (3 addresses, light and dark)")
    }
}
