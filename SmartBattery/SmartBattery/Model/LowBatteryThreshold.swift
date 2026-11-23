import SwiftUI

/// The estimated percent below which a battery counts as low. One value for the whole app (ADR-0001, decision 2).
enum LowBatteryThreshold {
    static let key = "lowPercentThreshold"
    static let range = 10...40
    static let step = 5
    static let defaultValue = 20

    /// The nearest allowed value: inside `range` and a multiple of `step`.
    static func normalized(_ value: Int) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    static func read(from defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: key) as? Int else { return defaultValue }
        return normalized(stored)
    }
}

extension EnvironmentValues {
    @Entry var lowBatteryThreshold: Int = LowBatteryThreshold.defaultValue
}
