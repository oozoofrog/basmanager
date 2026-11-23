import Foundation
import Observation

struct BatteryGroup: Codable, Identifiable, Equatable {
    struct Member: Codable, Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    struct Replacement: Codable, Identifiable, Equatable {
        var id = UUID()
        let date: Date
    }

    var id = UUID()
    var name = ""
    var members: [Member] = []
    var replacements: [Replacement] = []

    /// Whole days since the latest replacement, or nil when none is recorded.
    func daysSinceReplacement(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let latest = replacements.map(\.date).max() else { return nil }
        let from = calendar.startOfDay(for: latest)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: from, to: today).day ?? 0)
    }

    /// Registered batteries that belong to no device, in their registered order.
    static func ungrouped(_ registered: [RegisteredBattery], in groups: [BatteryGroup]) -> [RegisteredBattery] {
        let grouped = Set(groups.flatMap { $0.members.map(\.id) })
        return registered.filter { !grouped.contains($0.id) }
    }

    /// Translates a move inside a filtered list (`subset`) into offsets of the full list (`all`).
    static func moveOffsets(of subset: [UUID], in all: [UUID], from source: IndexSet, to destination: Int) -> (source: IndexSet, destination: Int)? {
        let positions = subset.compactMap { all.firstIndex(of: $0) }
        guard positions.count == subset.count, destination <= subset.count,
              source.allSatisfy({ $0 < subset.count }), let last = positions.last else { return nil }
        return (IndexSet(source.map { positions[$0] }), destination < subset.count ? positions[destination] : last + 1)
    }
}

@MainActor
@Observable
final class BatteryGroupStore {
    private(set) var groups: [BatteryGroup] = []
    private(set) var loadFailed = false
    private let fileURL: URL?

    init(fileURL: URL? = BatteryGroupStore.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL else {
            loadFailed = true
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            groups = Self.exclusive(try JSONDecoder().decode([BatteryGroup].self, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // There is no file until the first group is saved.
        } catch {
            loadFailed = true
        }
    }

    func update(_ group: BatteryGroup) throws {
        // A battery sits in one device, so saving it here takes it out of every other device.
        // A device that loses its last battery this way is deleted.
        let taken = Set(group.members.map(\.id))
        var updated: [BatteryGroup] = groups.compactMap { other in
            guard other.id != group.id else { return other }
            var other = other
            other.members.removeAll { taken.contains($0.id) }
            return other.members.isEmpty ? nil : other
        }
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            updated[index] = group
        } else {
            updated.append(group)
        }
        try save(updated)
    }

    func delete(_ id: UUID) throws {
        try save(groups.filter { $0.id != id })
    }

    /// Files written before the one-device rule may list a battery twice; the first device keeps it.
    /// A device left without batteries is dropped.
    private static func exclusive(_ groups: [BatteryGroup]) -> [BatteryGroup] {
        var seen = Set<UUID>()
        return groups.compactMap { group in
            var group = group
            group.members = group.members.filter { seen.insert($0.id).inserted }
            return group.members.isEmpty ? nil : group
        }
    }

    private func save(_ updated: [BatteryGroup]) throws {
        guard !loadFailed, let fileURL else { throw CocoaError(.fileWriteUnknown) }
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        groups = updated
    }

    static var defaultFileURL: URL? {
        BatteryStore.defaultFileURL?.deletingLastPathComponent().appending(path: "battery-groups.json")
    }
}

struct BatteryGroupCheck {
    struct Sample: Equatable {
        let percent: Int
        let isCharging: Bool
    }

    static let timeout = 10
    static let lowPercent = 20

    let id = UUID()
    let startedAt: Date
    let memberIDs: Set<UUID>
    private(set) var samples: [UUID: Sample] = [:]
    private(set) var endedAt: Date?
    private(set) var wasCancelled = false

    var isWaiting: Bool { endedAt == nil }

    var duration: TimeInterval? {
        endedAt.map { min(Double(Self.timeout), max(0, $0.timeIntervalSince(startedAt))) }
    }

    mutating func observe(_ batteries: [RegisteredBattery], at date: Date) {
        guard isWaiting else { return }
        let deadline = startedAt.addingTimeInterval(Double(Self.timeout))
        let registeredMembers = batteries.filter { memberIDs.contains($0.id) }
        for battery in registeredMembers where samples[battery.id] == nil {
            guard let seen = battery.lastSeen, seen >= startedAt, seen <= deadline, seen <= date,
                  let reading = battery.lastReading else { continue }
            samples[battery.id] = Sample(
                percent: CapacityTable.percent(
                    rawVoltage: reading.rawVoltage,
                    size: battery.sizeOverride ?? reading.reportedSize
                ),
                isCharging: reading.isCharging
            )
        }
        if date >= deadline || registeredMembers.allSatisfy({ samples[$0.id] != nil }) {
            endedAt = date
        }
    }

    mutating func cancel(at date: Date) {
        guard isWaiting else { return }
        wasCancelled = true
        endedAt = date
    }
}
