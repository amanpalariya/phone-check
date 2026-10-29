import Foundation

/// Current phone state shared by every transport; never stored as notification content.
public struct BatteryStatus: Codable, Equatable {
    public let percentage: Int?
    public let charging: Bool
    /// nil means an older peer did not supply Battery Saver state.
    public let powerSaving: Bool?
    public init(percentage: Int?, charging: Bool, powerSaving: Bool? = nil) {
        self.percentage = percentage; self.charging = charging; self.powerSaving = powerSaving
    }
    public var isValid: Bool { percentage.map { (0...100).contains($0) } ?? true }
}
