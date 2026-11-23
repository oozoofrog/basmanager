import ActivityKit
import Foundation

struct ChargingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let isCharging: Bool
        let percent: Int?
        let observedAt: Date
    }

    let batteryID: UUID
    let batteryName: String
}
