import AppKit
import SwiftUI

private final class PairingPresentation: ObservableObject {
    @Published var copiedCode = false
}

/// Pairing stays in the same transient surface as the notification feed.
struct PairingPane: View {
    @ObservedObject var model: Companion
    @ObservedObject private var account = CloudAccount.shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var presentation = PairingPresentation()

    var body: some View {
        VStack(spacing: 18) {
            if model.pairing {
                VStack(spacing: 6) {
                    Text("Scan to pair").font(.title2.weight(.semibold))
                    Text("Open Phone Check on Android.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                // QR ink and paper stay black-on-white in either appearance.
                PairingQRCodeView(code: model.code)
                    .environment(\.colorScheme, .light)
                if let expiry = model.pairingExpiresAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(ceil(expiry.timeIntervalSince(context.date))))
                        Text("Code expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                            .font(.callout.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if model.code.hasPrefix("pc1|") && model.addresses.count > 1 {
                    Picker("Mac address", selection: $model.host) {
                        ForEach(model.addresses, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu).controlSize(.small)
                }
                HStack(spacing: 10) {
                    Button(action: model.cancelPairing) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.code, forType: .string)
                        presentation.copiedCode = true
                    } label: {
                        Text(presentation.copiedCode ? "Copied" : "Copy code")
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.primary)
                    .help("Paste this code into Phone Check on Android")
                }
                .modifier(NativePrimaryAction())
            } else {
                PairingDevices()
                    .padding(.top, 8).padding(.bottom, 4)
                VStack(spacing: 7) {
                    Text("Your phone, right here.").font(.title2.weight(.semibold))
                    Text(account.signedIn ? "Bring your Android notifications to Mac." : "Connect both devices to the same network.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button(model.listening || !account.signedIn ? "Pair phone" : "Retry connection") {
                    if model.listening || !account.signedIn { model.beginPairing() } else { model.startListening() }
                }
                .modifier(NativePrimaryAction())
                if account.signedIn {
                    Text("Pair once. Connect wherever you are online.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(account.busy ? "Signing in…" : "Sign in for cloud sync", action: account.signIn)
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(account.busy || !account.configured)
                    if let error = account.error { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
        }
        .onChange(of: model.code) { _, _ in presentation.copiedCode = false }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
    }
}

private struct PairingDevices: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 46, weight: .ultraLight))
            Image(systemName: "link")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: Circle())
            Image(systemName: "iphone")
                .font(.system(size: 43, weight: .ultraLight))
        }
        .foregroundStyle(.primary)
        .frame(height: 64)
        .accessibilityHidden(true)
    }
}
