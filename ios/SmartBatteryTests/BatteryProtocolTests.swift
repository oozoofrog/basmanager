import Foundation
import Testing
@testable import SmartBattery

struct BatteryProtocolTests {
    @Test func decodesAdvertisement() throws {
        // voltage 0x5F << 2 | 0b10 = 382, AAA bit set, charging, count 0x0102
        let data = Data([0x59, 0x00, 0x5F, 0b1000_0011, 0x01, 0x02])
        let reading = try #require(BatteryReading(manufacturerData: data))
        #expect(reading.rawVoltage == 382)
        #expect(reading.reportedSize == .aaa)
        #expect(reading.isCharging)
        #expect(reading.chargeCount == 258)
    }

    @Test func missingChargeCountIsNil() throws {
        let reading = try #require(BatteryReading(manufacturerData: Data([0, 0, 0x60, 0x00, 0xFF, 0xFF])))
        #expect(reading.chargeCount == nil)
        #expect(reading.reportedSize == .aa)
        #expect(!reading.isCharging)
    }

    @Test func rejectsShortAdvertisement() {
        #expect(BatteryReading(manufacturerData: Data([0, 0, 0x60, 0x00, 0x01])) == nil)
    }

    @Test func decodesConnectionResponse() throws {
        let response = Data([0xE2, 0x44, 0x59, 0x00, 0x5F, 0b1000_0010, 0x00, 0x07])
        let reading = try #require(BatteryReading(response: response))
        #expect(reading.rawVoltage == 382)
        #expect(reading.reportedSize == .aaa)
        #expect(reading.chargeCount == 7)
        #expect(BatteryReading(response: Data([0xE2, 0x45, 0, 0, 0, 0, 0, 0])) == nil)
    }

    @Test func capacityTableBounds() {
        #expect(CapacityTable.aaa.count == 54)
        #expect(CapacityTable.aa.count == 74)
        #expect(CapacityTable.percent(rawVoltage: 407, size: .aaa) == 100)
        #expect(CapacityTable.percent(rawVoltage: 406, size: .aaa) == 99)
        #expect(CapacityTable.percent(rawVoltage: 355, size: .aaa) == 6)
        #expect(CapacityTable.percent(rawVoltage: 354, size: .aaa) == 5)
        #expect(CapacityTable.percent(rawVoltage: 408, size: .aa) == 100)
        #expect(CapacityTable.percent(rawVoltage: 336, size: .aa) == 5)
        #expect(CapacityTable.percent(rawVoltage: 335, size: .aa) == 5)
        #expect(CapacityTable.percent(rawVoltage: 383, size: .aa) == 80)
    }

    @Test @MainActor func unregisteredDisappearsAfterOfflineInterval() {
        let store = BatteryStore(fileURL: nil)
        let id = UUID()
        let start = Date()
        store.record(BatteryReading(rawVoltage: 390, isCharging: false, reportedSize: .aa, chargeCount: 3), rssi: -60, from: id, at: start)
        store.tick(start)
        #expect(store.unregistered.map(\.id) == [id])
        store.tick(start.addingTimeInterval(36))
        #expect(store.unregistered.isEmpty)
    }

    @Test @MainActor func registrationKeepsLastReading() {
        let store = BatteryStore(fileURL: nil)
        let id = UUID()
        store.record(BatteryReading(rawVoltage: 390, isCharging: false, reportedSize: .aaa, chargeCount: 3), rssi: -60, from: id)
        #expect(store.register(id, name: "  도어락 "))
        #expect(!store.register(id, name: "중복"))
        #expect(store.registered.first?.name == "도어락")
        #expect(store.percent(for: store.registered[0]) == CapacityTable.percent(rawVoltage: 390, size: .aaa))
        #expect(store.unregistered.isEmpty)
    }
    @Test @MainActor func chargeStartIsDetectedOnlyOnTransition() {
        let store = BatteryStore(fileURL: nil)
        let id = UUID()
        let start = Date()
        func reading(_ charging: Bool) -> BatteryReading {
            BatteryReading(rawVoltage: 380, isCharging: charging, reportedSize: .aa, chargeCount: 1)
        }
        // First sighting already charging: not a transition.
        store.record(reading(true), rssi: -60, from: id, at: start)
        store.tick(start)
        #expect(store.recentlyStartedCharging.isEmpty)

        store.record(reading(false), rssi: -60, from: id, at: start.addingTimeInterval(1))
        store.record(reading(true), rssi: -60, from: id, at: start.addingTimeInterval(2))
        store.tick(start.addingTimeInterval(2))
        #expect(store.recentlyStartedCharging == [id])

        store.tick(start.addingTimeInterval(2 + BatteryStore.chargeHighlightInterval + 1))
        #expect(store.recentlyStartedCharging.isEmpty)
    }

    @Test func proximityBuckets() {
        #expect(Proximity(rssi: -45) == .veryClose)
        #expect(Proximity(rssi: -60) == .close)
        #expect(Proximity(rssi: -75) == .near)
        #expect(Proximity(rssi: -90) == .far)
        #expect(Proximity.near < Proximity.close)
    }
}
