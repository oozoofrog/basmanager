import Foundation
import Testing
@testable import SmartBattery

@MainActor
struct ChargingStoreTests {
    @Test func chargingObservationsSeparateSignalsFromReceptionGaps() {
        let store = BatteryStore(fileURL: nil)
        let id = UUID()
        let start = Date()
        #expect(store.register(id, name: "작업등"))

        store.record(reading(charging: true), rssi: -60, from: id, at: start)
        store.updateRSSI(-65, for: id, at: start.addingTimeInterval(34))
        store.tick(start.addingTimeInterval(36))
        if let battery = store.battery(id) {
            #expect(!store.hasFreshReading(for: battery))
        }
        #expect(store.sightings[id] != nil)
        store.record(reading(charging: false), rssi: nil, from: id, at: start.addingTimeInterval(37))
        #expect(store.chargeHistory.map(\.kind) == [.alreadyCharging, .receptionInterrupted])
        #expect(store.chargeHistory.last?.date == start)

        store.record(reading(charging: true), rssi: nil, from: id, at: start.addingTimeInterval(38))
        store.record(reading(charging: false), rssi: nil, from: id, at: start.addingTimeInterval(39))
        #expect(store.chargeHistory.suffix(2).map(\.kind) == [.started, .chargingSignalEnded])
    }

    @Test func chargeGoalNotifiesOncePerSelectedBatteryAndMonitoringSession() {
        let store = BatteryStore(fileURL: nil)
        let selected = UUID()
        let other = UUID()
        let start = Date()
        #expect(store.register(selected, name: "조명 1"))
        #expect(store.register(other, name: "조명 2"))
        store.record(reading(charging: true), rssi: -60, from: selected, at: start)
        store.startChargeGoalMonitoring(for: [selected])
        #expect(store.chargeGoalNotices.isEmpty)

        store.record(reading(charging: true), rssi: -60, from: other, at: start)
        store.record(reading(charging: false), rssi: -60, from: selected, at: start.addingTimeInterval(1))
        store.record(reading(charging: true, rawVoltage: 350), rssi: -60, from: selected, at: start.addingTimeInterval(2))
        #expect(store.chargeGoalNotices.isEmpty)

        var noticeCountsOnReading: [Int] = []
        store.onReading = { [weak store] in
            if let store { noticeCountsOnReading.append(store.chargeGoalNotices.count) }
        }
        store.record(reading(charging: true), rssi: -60, from: selected, at: start.addingTimeInterval(3))
        store.record(reading(charging: true), rssi: -60, from: selected, at: start.addingTimeInterval(4))
        #expect(noticeCountsOnReading == [1, 1])
        #expect(store.chargeGoalNotices.map(\.batteryID) == [selected])

        store.stopChargeGoalMonitoring()
        store.startChargeGoalMonitoring(for: [selected, other])
        store.record(reading(charging: true), rssi: -60, from: selected, at: start.addingTimeInterval(5))
        store.record(reading(charging: true), rssi: -60, from: other, at: start.addingTimeInterval(5))
        #expect(store.chargeGoalNotices.map(\.batteryID) == [selected, other])
    }

    @Test func chargeHistoryPersistsAlongsideExistingRegistrations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("registered-batteries.json")
        let id = UUID()
        let start = Date()
        let existing = RegisteredBattery(id: id, name: "카메라", lastReading: reading(charging: true), lastSeen: start)
        try JSONEncoder().encode([existing]).write(to: fileURL)

        let store = BatteryStore(fileURL: fileURL)
        #expect(store.registered == [existing])
        #expect(!store.hasFreshReading(for: existing))
        store.setChargeGoal(85)
        store.record(reading(charging: true), rssi: -58, from: id, at: start.addingTimeInterval(1))
        store.record(reading(charging: false), rssi: -58, from: id, at: start.addingTimeInterval(2))

        let reloaded = BatteryStore(fileURL: fileURL)
        #expect(reloaded.registered.map(\.name) == ["카메라"])
        #expect(reloaded.chargeGoal == 85)
        #expect(reloaded.chargeHistory.map(\.kind) == [.alreadyCharging, .chargingSignalEnded])
        #expect(reloaded.monitoredChargeIDs.isEmpty)
    }

    @Test func chargeSettingsCanBeRetriedAfterASaveFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let chargingURL = directory.appendingPathComponent("registered-batteries.charging.json", isDirectory: true)
        try FileManager.default.createDirectory(at: chargingURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("registered-batteries.json")
        let store = BatteryStore(fileURL: fileURL)
        store.setChargeGoal(90)
        #expect(store.chargingSaveFailed)
        #expect(store.chargeGoal == 90)

        try FileManager.default.removeItem(at: chargingURL)
        store.retrySavingCharging()
        #expect(!store.chargingSaveFailed)
        #expect(BatteryStore(fileURL: fileURL).chargeGoal == 90)
    }

    private func reading(charging: Bool, rawVoltage: Int = 408) -> BatteryReading {
        BatteryReading(rawVoltage: rawVoltage, isCharging: charging, reportedSize: .aa, chargeCount: nil)
    }
}
