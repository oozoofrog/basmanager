import Foundation
import Observation

/// A battery the user registered. `id` is the CoreBluetooth peripheral identifier,
/// which is stable only on this iPhone.
struct RegisteredBattery: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// Overrides the size bit from the advertisement. See ``BatteryStore/effectiveSize(for:)``.
    var sizeOverride: BatterySize?
    var keepConnected: Bool = false
    var lastReading: BatteryReading?
    var lastSeen: Date?
}

/// Latest advertisement from a battery in range.
struct Sighting: Equatable, Sendable {
    var reading: BatteryReading
    var rssi: Int
    var lastSeen: Date
}

struct ChargeObservation: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case started
        case alreadyCharging
        case chargingSignalEnded
        case receptionInterrupted
    }

    let id: UUID
    let batteryID: UUID
    let date: Date
    let kind: Kind
    let percent: Int?
    let chargeCount: Int?
}

struct ChargeGoalNotice: Identifiable, Equatable {
    let id = UUID()
    let batteryID: UUID
    let batteryName: String
    let percent: Int
    let goal: Int
}

enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting(since: Date)
    case connected
    case failed
}

@MainActor
@Observable
final class BatteryStore {
    private(set) var registered: [RegisteredBattery] = []
    private(set) var sightings: [UUID: Sighting] = [:]
    var connections: [UUID: ConnectionStatus] = [:]
    /// Advanced once per second so online/offline state refreshes.
    private(set) var now = Date()
    /// When each battery in range switched from not charging to charging.
    private(set) var chargeStarts: [UUID: Date] = [:]
    private(set) var chargeHistory: [ChargeObservation] = []
    private(set) var chargeGoal = 80
    private(set) var monitoredChargeIDs: Set<UUID> = []
    private(set) var reachedChargeGoalIDs: Set<UUID> = []
    private(set) var chargeGoalNotices: [ChargeGoalNotice] = []
    private(set) var chargingSaveFailed = false
    /// The battery file exists but could not be read or decoded. Nothing is written and changes are refused,
    /// so the file stays as it is (ADR-0001, decisions 4 and 11).
    private(set) var batteryLoadFailed = false
    /// The charging file exists but could not be read or decoded. It is never written (ADR-0001, decision 10).
    private(set) var chargingLoadFailed = false

    @ObservationIgnored var onReading: (() -> Void)?
    private var lastDecodedAt: [UUID: Date] = [:]

    /// How long a battery that started charging stays highlighted.
    static let chargeHighlightInterval: TimeInterval = 60
    static let chargeGoalRange = 5...100
    /// The next action shown with a load failure. Deleting the app would also delete the files, so it is not suggested.
    static let loadFailureNextAction = String(localized: "최신 버전을 설치하거나 iPhone 백업에서 복원하세요. 그때까지 바꾼 내용은 저장되지 않아요.")
    private static let chargeHistoryLimit = 200

    private struct SavedCharging: Codable {
        var goal: Int
        var history: [ChargeObservation]
    }

    private let fileURL: URL?
    private let chargingFileURL: URL?

    /// - Parameter fileURL: The battery file. `nil` creates an in-memory store for tests and previews.
    init(fileURL: URL?) {
        self.fileURL = fileURL
        chargingFileURL = fileURL?.deletingPathExtension().appendingPathExtension("charging.json")
        load()
    }

    /// The store the app uses. An unavailable Application Support folder counts as a load failure.
    static func onDevice() -> BatteryStore {
        guard let fileURL = defaultFileURL else {
            let store = BatteryStore(fileURL: nil)
            store.batteryLoadFailed = true
            store.chargingLoadFailed = true
            return store
        }
        return BatteryStore(fileURL: fileURL)
    }

    // MARK: Derived state

    var unregistered: [(id: UUID, sighting: Sighting)] {
        let known = Set(registered.map(\.id))
        return sightings
            .filter { !known.contains($0.key) && isOnline($0.value.lastSeen) }
            .map { (id: $0.key, sighting: $0.value) }
            .sorted { $0.sighting.rssi > $1.sighting.rssi }
    }

    /// Batteries that started charging recently, newest first. Plugging a battery into the
    /// charger flips its charging bit, which identifies that physical battery.
    var recentlyStartedCharging: [UUID] {
        chargeStarts
            .filter { now.timeIntervalSince($0.value) <= Self.chargeHighlightInterval }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    var canRegisterMore: Bool { registered.count < BatteryProtocol.registrationLimit }

    func isOnline(_ battery: RegisteredBattery) -> Bool {
        guard let seen = battery.lastSeen else { return false }
        return isOnline(seen)
    }

    func isOnline(_ date: Date) -> Bool {
        now.timeIntervalSince(date) <= BatteryProtocol.offlineInterval
    }

    func hasFreshReading(for battery: RegisteredBattery) -> Bool {
        guard let date = lastDecodedAt[battery.id] else { return false }
        return isOnline(date)
    }

    func effectiveSize(for battery: RegisteredBattery) -> BatterySize? {
        battery.sizeOverride ?? battery.lastReading?.reportedSize
    }

    func percent(for battery: RegisteredBattery) -> Int? {
        guard let reading = battery.lastReading, let size = effectiveSize(for: battery) else { return nil }
        return CapacityTable.percent(rawVoltage: reading.rawVoltage, size: size)
    }

    func battery(_ id: UUID) -> RegisteredBattery? {
        registered.first { $0.id == id }
    }

    // MARK: Updates from Bluetooth

    func tick(_ date: Date = Date()) {
        now = date
        let expiredIDs = lastDecodedAt.compactMap { id, lastDate in
            date.timeIntervalSince(lastDate) > BatteryProtocol.offlineInterval ? id : nil
        }
        var historyChanged = false
        for id in expiredIDs {
            if expireReading(id) { historyChanged = true }
        }
        if historyChanged { saveCharging() }
        sightings = sightings.filter { date.timeIntervalSince($0.value.lastSeen) <= BatteryProtocol.offlineInterval }
        chargeStarts = chargeStarts.filter { date.timeIntervalSince($0.value) <= Self.chargeHighlightInterval }
    }

    /// RSSI read over an open connection, used while a connected battery stops advertising.
    func updateRSSI(_ rssi: Int, for id: UUID, at date: Date = Date()) {
        guard sightings[id] != nil else { return }
        sightings[id]?.rssi = rssi
        sightings[id]?.lastSeen = date
    }

    func record(_ reading: BatteryReading, rssi: Int?, from id: UUID, at date: Date = Date()) {
        var historyChanged = false
        if let lastDate = lastDecodedAt[id], date.timeIntervalSince(lastDate) > BatteryProtocol.offlineInterval {
            historyChanged = expireReading(id)
        }
        let previous = lastDecodedAt[id] == nil ? nil : sightings[id]?.reading
        let observation: ChargeObservation.Kind? = switch (previous?.isCharging, reading.isCharging) {
        case (false?, true): .started
        case (nil, true): .alreadyCharging
        case (true?, false): .chargingSignalEnded
        default: nil
        }
        if observation == .started { chargeStarts[id] = date }
        if !reading.isCharging {
            chargeStarts[id] = nil
        }
        let previousRSSI = sightings[id]?.rssi ?? 0
        sightings[id] = Sighting(reading: reading, rssi: rssi ?? previousRSSI, lastSeen: date)
        lastDecodedAt[id] = date
        guard let index = registered.firstIndex(where: { $0.id == id }) else { return }
        let changed = registered[index].lastReading != reading
        registered[index].lastReading = reading
        registered[index].lastSeen = date
        // Persist only when the reading changes.
        if changed { save() }
        let battery = registered[index]
        if let observation {
            appendChargeObservation(observation, for: battery, at: date)
            historyChanged = true
        }
        if historyChanged { saveCharging() }
        if reading.isCharging,
           monitoredChargeIDs.contains(id),
           let percent = percent(for: battery), percent >= chargeGoal,
           reachedChargeGoalIDs.insert(id).inserted {
            chargeGoalNotices.append(ChargeGoalNotice(batteryID: id, batteryName: battery.name, percent: percent, goal: chargeGoal))
        }
        onReading?()
    }

    private func expireReading(_ id: UUID) -> Bool {
        guard let lastDate = lastDecodedAt.removeValue(forKey: id),
              let battery = battery(id), battery.lastReading?.isCharging == true else { return false }
        appendChargeObservation(.receptionInterrupted, for: battery, at: lastDate, includesReading: false)
        return true
    }

    private func appendChargeObservation(
        _ kind: ChargeObservation.Kind,
        for battery: RegisteredBattery,
        at date: Date,
        includesReading: Bool = true
    ) {
        // A charging file that could not be read keeps an empty history (AC-3.9).
        guard !chargingLoadFailed else { return }
        chargeHistory.append(ChargeObservation(
            id: UUID(), batteryID: battery.id, date: date, kind: kind,
            percent: includesReading ? percent(for: battery) : nil,
            chargeCount: includesReading ? battery.lastReading?.chargeCount : nil
        ))
        if chargeHistory.count > Self.chargeHistoryLimit {
            chargeHistory.removeFirst()
        }
    }

    // MARK: User actions

    @discardableResult
    func register(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batteryLoadFailed, canRegisterMore, !trimmed.isEmpty, battery(id) == nil else { return false }
        let sighting = sightings[id]
        let battery = RegisteredBattery(
            id: id,
            name: trimmed,
            lastReading: sighting?.reading,
            lastSeen: lastDecodedAt[id]
        )
        registered.append(battery)
        save()
        if battery.lastReading?.isCharging == true, let date = battery.lastSeen, isOnline(date) {
            appendChargeObservation(.alreadyCharging, for: battery, at: date)
            saveCharging()
        }
        return true
    }

    func update(_ battery: RegisteredBattery) {
        guard !batteryLoadFailed, let index = registered.firstIndex(where: { $0.id == battery.id }) else { return }
        registered[index] = battery
        save()
    }

    func delete(_ id: UUID) {
        guard !batteryLoadFailed else { return }
        registered.removeAll { $0.id == id }
        monitoredChargeIDs.remove(id)
        reachedChargeGoalIDs.remove(id)
        chargeGoalNotices.removeAll { $0.batteryID == id }
        chargeHistory.removeAll { $0.batteryID == id }
        save()
        saveCharging()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard !batteryLoadFailed else { return }
        registered.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func setChargeGoal(_ goal: Int) {
        guard canWriteCharging, monitoredChargeIDs.isEmpty, Self.chargeGoalRange.contains(goal), chargeGoal != goal else { return }
        chargeGoal = goal
        saveCharging()
    }

    func startChargeGoalMonitoring(for ids: Set<UUID>) {
        guard monitoredChargeIDs.isEmpty else { return }
        monitoredChargeIDs = ids.intersection(registered.map(\.id))
        reachedChargeGoalIDs = []
    }

    func stopChargeGoalMonitoring() {
        monitoredChargeIDs = []
        reachedChargeGoalIDs = []
        chargeGoalNotices = []
    }

    func dismissChargeGoalNotice(_ id: UUID) {
        chargeGoalNotices.removeAll { $0.id == id }
    }

    func retrySavingCharging() {
        saveCharging()
    }

    // MARK: Persistence

    static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "registered-batteries.json")
    }

    private enum FileRead {
        case missing
        case contents(Data)
        case failed
    }

    /// Only "no such file" means missing. Every other read error is a failure, so the file is kept.
    private static func read(_ url: URL) -> FileRead {
        do {
            return .contents(try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .failed
        }
    }

    private var canWriteCharging: Bool { !batteryLoadFailed && !chargingLoadFailed }

    private func load() {
        guard let fileURL else { return }
        switch Self.read(fileURL) {
        case .missing:
            break
        case .contents(let data):
            if let decoded = try? JSONDecoder().decode([RegisteredBattery].self, from: data) {
                registered = decoded
            } else {
                batteryLoadFailed = true
            }
        case .failed:
            batteryLoadFailed = true
        }

        guard let chargingFileURL else { return }
        switch Self.read(chargingFileURL) {
        case .missing:
            break
        case .contents(let data):
            guard let saved = try? JSONDecoder().decode(SavedCharging.self, from: data) else {
                chargingLoadFailed = true
                return
            }
            if Self.chargeGoalRange.contains(saved.goal) { chargeGoal = saved.goal }
            // Without the battery list, keep the whole history so the count stays honest; it is never saved then.
            let registeredIDs = Set(registered.map(\.id))
            let history = batteryLoadFailed ? saved.history : saved.history.filter { registeredIDs.contains($0.batteryID) }
            chargeHistory = Array(history.suffix(Self.chargeHistoryLimit))
        case .failed:
            chargingLoadFailed = true
        }
    }

    private func save() {
        guard !batteryLoadFailed, let fileURL else { return }
        do {
            try JSONEncoder().encode(registered).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Saving batteries failed: \(error)")
        }
    }

    private func saveCharging() {
        guard canWriteCharging, let chargingFileURL else { return }
        do {
            let saved = SavedCharging(goal: chargeGoal, history: chargeHistory)
            try JSONEncoder().encode(saved).write(to: chargingFileURL, options: .atomic)
            chargingSaveFailed = false
        } catch {
            chargingSaveFailed = true
        }
    }
}
