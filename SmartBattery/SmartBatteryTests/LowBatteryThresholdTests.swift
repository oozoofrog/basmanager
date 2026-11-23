import Foundation
import SwiftUI
import Testing
@testable import SmartBattery

struct LowBatteryThresholdTests {
    private func defaults() -> UserDefaults {
        let name = "LowBatteryThresholdTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("AC-4.1 the threshold defaults to 20 and persists")
    func lowThresholdPersistsAndDefaults() {
        let defaults = defaults()
        #expect(LowBatteryThreshold.read(from: defaults) == 20)
        defaults.set(30, forKey: LowBatteryThreshold.key)
        #expect(LowBatteryThreshold.read(from: defaults) == 30)
    }

    @Test("AC-4.2 a stored threshold is read as the nearest allowed value")
    func lowThresholdClampsStoredValue() {
        #expect(LowBatteryThreshold.normalized(5) == 10)
        #expect(LowBatteryThreshold.normalized(10) == 10)
        #expect(LowBatteryThreshold.normalized(23) == 25)
        #expect(LowBatteryThreshold.normalized(22) == 20)
        #expect(LowBatteryThreshold.normalized(40) == 40)
        #expect(LowBatteryThreshold.normalized(90) == 40)
        let defaults = defaults()
        defaults.set(3, forKey: LowBatteryThreshold.key)
        #expect(LowBatteryThreshold.read(from: defaults) == 10)
    }

    @Test("AC-4.3 battery rows use the threshold for color and symbol")
    func batteryLevelUsesThreshold() {
        // Threshold 30: 29 is low, 30 is the middle band.
        #expect(BatteryLevel.symbol(percent: 29, charging: false, threshold: 30) == "battery.25percent")
        #expect(BatteryLevel.color(percent: 29, threshold: 30) == .red)
        #expect(BatteryLevel.symbol(percent: 30, charging: false, threshold: 30) == "battery.50percent")
        #expect(BatteryLevel.color(percent: 30, threshold: 30) == .orange)
        // Threshold 10: 15 is the middle band, not low.
        #expect(BatteryLevel.symbol(percent: 15, charging: false, threshold: 10) == "battery.50percent")
        #expect(BatteryLevel.color(percent: 15, threshold: 10) == .orange)
        // A charging battery keeps the bolt symbol and uses the threshold only for color.
        #expect(BatteryLevel.symbol(percent: 15, charging: true, threshold: 30) == "battery.100percent.bolt")
        #expect(BatteryLevel.color(percent: 15, threshold: 30) == .red)
    }

    @Test("AC-4.4 a device check reports low exactly below the threshold")
    func checkStatusUsesThreshold() {
        let at25 = BatteryGroupCheck.Sample(percent: 25, isCharging: false)
        #expect(BatteryGroupCheckStatus(sample: at25, isWaiting: false, lowThreshold: 30) == .low)
        #expect(BatteryGroupCheckStatus(sample: at25, isWaiting: false, lowThreshold: 25) == .received)
        #expect(BatteryGroupCheckStatus(sample: at25, isWaiting: false, lowThreshold: 20) == .received)
    }
}
