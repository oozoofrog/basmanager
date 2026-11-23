import ActivityKit
import Foundation

/// Live Activity attributes. The app and the Live Activity extension each compile their own copy:
/// SmartBattery/Model/ChargingActivityAttributes.swift and SmartBatteryLiveActivity/ChargingActivityAttributes.swift.
/// Keep both copies identical; ActivityKit matches the type by name and shape.
struct ChargingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let isCharging: Bool
        let percent: Int?
        let observedAt: Date
    }

    let batteryID: UUID
    let batteryName: String
}
