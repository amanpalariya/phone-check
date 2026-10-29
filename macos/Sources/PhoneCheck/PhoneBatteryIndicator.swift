import SwiftUI
import PhoneCheckCore

struct PhoneBatteryIndicator: View {
    let battery: BatteryStatus?
    let connected: Bool
    let status: String
    private var reading: BatteryStatus? { connected ? battery : nil }
    private var symbol: String {
        if reading?.charging == true { return "battery.100percent.bolt" }
        guard let percentage = reading?.percentage else { return "battery.0percent" }
        switch percentage {
        case 0..<10: return "battery.0percent"
        case 10..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    private var label: String {
        guard connected else { return status }
        guard let reading else { return "Phone battery unavailable" }
        var parts = [reading.percentage.map { "Phone battery \($0)%" } ?? "Phone battery unavailable"]
        if reading.charging { parts.append(reading.percentage == 100 ? "fully charged" : "charging") }
        if reading.powerSaving == true { parts.append("Battery Saver on") }
        return parts.joined(separator: ", ")
    }
    private var batteryColor: Color {
        if reading?.charging == true { return Color(nsColor: .systemGreen) }
        if reading?.powerSaving == true { return Color(nsColor: .systemOrange) }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(reading?.percentage.map { "\($0)%" } ?? "—")
                .font(.caption).monospacedDigit()
            if reading?.powerSaving == true {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(batteryColor)
        }
        .foregroundStyle(.secondary)
        .frame(minHeight: 28)
        .fixedSize()
        .help(label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
