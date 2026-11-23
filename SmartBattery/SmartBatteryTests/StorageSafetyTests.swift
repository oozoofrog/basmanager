import Foundation
import Testing
@testable import SmartBattery

@MainActor
struct StorageSafetyTests {
    private let folder: URL
    private let batteryURL: URL
    private let chargingURL: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        batteryURL = folder.appending(path: "registered-batteries.json")
        chargingURL = folder.appending(path: "registered-batteries.charging.json")
    }

    private func reading(charging: Bool, voltage: Int = 380) -> BatteryReading {
        BatteryReading(rawVoltage: voltage, isCharging: charging, reportedSize: .aa, chargeCount: 3)
    }

    private func writeValidFiles(batteryID: UUID) throws {
        let battery = RegisteredBattery(id: batteryID, name: "도어락")
        try JSONEncoder().encode([battery]).write(to: batteryURL)
        let charging = #"{"goal":70,"history":[]}"#
        try Data(charging.utf8).write(to: chargingURL)
    }

    @Test("AC-3.1 load failure never overwrites the battery file")
    func loadFailureNeverOverwritesBatteryFile() throws {
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: batteryURL)
        let store = BatteryStore(fileURL: batteryURL)
        #expect(store.batteryLoadFailed)

        let id = UUID()
        store.record(reading(charging: false), rssi: -60, from: id)
        _ = store.register(id, name: "새 건전지")
        #expect(try Data(contentsOf: batteryURL) == corrupt)
    }

    @Test("AC-3.2 load failure never overwrites the charging file")
    func loadFailureNeverOverwritesChargingFile() throws {
        try Data("not json".utf8).write(to: batteryURL)
        let charging = Data(#"{"goal":70,"history":[]}"#.utf8)
        try charging.write(to: chargingURL)
        let store = BatteryStore(fileURL: batteryURL)

        store.setChargeGoal(90)
        store.retrySavingCharging()
        let id = UUID()
        store.record(reading(charging: false), rssi: -60, from: id)
        store.record(reading(charging: true), rssi: -60, from: id)
        store.tick(Date().addingTimeInterval(120))
        #expect(try Data(contentsOf: chargingURL) == charging)
    }

    @Test("AC-3.3 load failure refuses every change")
    func loadFailureRefusesChanges() throws {
        try Data("not json".utf8).write(to: batteryURL)
        let store = BatteryStore(fileURL: batteryURL)
        let id = UUID()
        store.record(reading(charging: false), rssi: -60, from: id)

        #expect(!store.register(id, name: "새 건전지"))
        store.update(RegisteredBattery(id: id, name: "바뀐 이름"))
        store.delete(id)
        store.move(from: IndexSet(integer: 0), to: 0)
        #expect(store.registered.isEmpty)
    }

    @Test("AC-3.5 a missing battery file is not a failure")
    func missingBatteryFileIsNotAFailure() throws {
        let store = BatteryStore(fileURL: batteryURL)
        #expect(!store.batteryLoadFailed)
        #expect(!store.chargingLoadFailed)
        #expect(store.registered.isEmpty)

        let id = UUID()
        store.record(reading(charging: false), rssi: -60, from: id)
        #expect(store.register(id, name: "새 건전지"))
        #expect(BatteryStore(fileURL: batteryURL).registered.map(\.name) == ["새 건전지"])
    }

    @Test("AC-3.6 an unreadable battery file is a failure")
    func unreadableBatteryFileIsAFailure() throws {
        try FileManager.default.createDirectory(at: batteryURL, withIntermediateDirectories: false)
        let store = BatteryStore(fileURL: batteryURL)
        #expect(store.batteryLoadFailed)
        #expect(!store.register(UUID(), name: "새 건전지"))
    }

    @Test("AC-3.9 a charging load failure never overwrites the charging file")
    func chargingLoadFailureNeverOverwritesChargingFile() throws {
        let id = UUID()
        try writeValidFiles(batteryID: id)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: chargingURL)
        let store = BatteryStore(fileURL: batteryURL)
        #expect(store.chargingLoadFailed)
        #expect(!store.batteryLoadFailed)
        #expect(store.chargeGoal == 80)

        store.setChargeGoal(90)
        #expect(store.chargeGoal == 80)
        store.record(reading(charging: false), rssi: -60, from: id)
        store.record(reading(charging: true), rssi: -60, from: id)
        store.retrySavingCharging()
        #expect(try Data(contentsOf: chargingURL) == corrupt)
        // The battery file still loads and saves normally.
        #expect(BatteryStore(fileURL: batteryURL).registered.first?.lastReading?.isCharging == true)
    }

    @Test("AC-3.12 an in-memory store accepts changes")
    func inMemoryStoreAcceptsChanges() {
        let store = BatteryStore(fileURL: nil)
        let id = UUID()
        store.record(reading(charging: false), rssi: -60, from: id)
        #expect(store.register(id, name: "새 건전지"))
        store.setChargeGoal(90)
        #expect(store.chargeGoal == 90)
        #expect(!store.batteryLoadFailed)
        #expect(!store.chargingLoadFailed)
    }
}
