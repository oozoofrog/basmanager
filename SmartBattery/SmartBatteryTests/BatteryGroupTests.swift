import Foundation
import Testing
@testable import SmartBattery

struct BatteryGroupTests {
    @Test func checkShowsFreshAnswersWhileWaitingAndFinishesOnLastAnswer() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        var first = battery(at: startedAt.addingTimeInterval(-1), rawVoltage: 335)
        var second = battery(at: startedAt.addingTimeInterval(-1), rawVoltage: 408)
        var check = BatteryGroupCheck(startedAt: startedAt, memberIDs: [first.id, second.id])

        check.observe([first, second], at: startedAt)
        #expect(check.samples.isEmpty)
        #expect(check.isWaiting)

        first.lastSeen = startedAt.addingTimeInterval(1)
        let firstReception = startedAt.addingTimeInterval(1)
        check.observe([first, second], at: firstReception)
        #expect(check.samples[first.id]?.percent == 5)
        #expect(check.samples[second.id] == nil)
        #expect(check.isWaiting)

        second.lastSeen = startedAt.addingTimeInterval(2)
        check.observe([first, second], at: startedAt.addingTimeInterval(2))
        #expect(check.samples[second.id]?.percent == 100)
        #expect(check.duration == 2)
    }

    @Test func timeoutPreservesPartialAnswersAndRejectsLaterSamples() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        let first = battery(at: startedAt.addingTimeInterval(2), rawVoltage: 335)
        let late = battery(at: startedAt.addingTimeInterval(11), rawVoltage: 408)
        var check = BatteryGroupCheck(startedAt: startedAt, memberIDs: [first.id, late.id])

        check.observe([first, late], at: startedAt.addingTimeInterval(11))
        #expect(check.samples[first.id]?.percent == 5)
        #expect(check.samples[late.id] == nil)
        #expect(!check.isWaiting)
        #expect(check.duration == Double(BatteryGroupCheck.timeout))
    }

    @Test func removedRegistrationRemainsInGroupWithoutDelayingAvailableAnswers() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        let removed = UUID()
        let available = battery(at: startedAt.addingTimeInterval(1), rawVoltage: 408)
        var check = BatteryGroupCheck(startedAt: startedAt, memberIDs: [available.id, removed])

        check.observe([available], at: startedAt.addingTimeInterval(1))
        #expect(check.memberIDs.contains(removed))
        #expect(check.samples[removed] == nil)
        #expect(check.duration == 1)
    }

    private func battery(at date: Date, rawVoltage: Int) -> RegisteredBattery {
        RegisteredBattery(
            id: UUID(),
            name: "AA",
            lastReading: BatteryReading(rawVoltage: rawVoltage, isCharging: false, reportedSize: .aa, chargeCount: nil),
            lastSeen: date
        )
    }

    @Test func ungroupedKeepsRegisteredOrderAndSkipsMembers() {
        let a = RegisteredBattery(id: UUID(), name: "A"), b = RegisteredBattery(id: UUID(), name: "B")
        let c = RegisteredBattery(id: UUID(), name: "C")
        let group = BatteryGroup(name: "플래시", members: [.init(id: b.id, name: "B")])
        #expect(BatteryGroup.ungrouped([a, b, c], in: [group]).map(\.name) == ["A", "C"])
        #expect(BatteryGroup.ungrouped([a, b, c], in: []).map(\.name) == ["A", "B", "C"])
    }

    @Test func moveInFilteredListMapsToFullList() throws {
        let ids = (0..<5).map { _ in UUID() }
        // Ungrouped rows are full-list positions 0, 2 and 4.
        let subset = [ids[0], ids[2], ids[4]]
        for (from, to) in [(0, 3), (2, 0), (0, 2), (1, 3)] {
            let move = try #require(BatteryGroup.moveOffsets(of: subset, in: ids, from: IndexSet(integer: from), to: to))
            var all = ids, expected = subset
            all.move(fromOffsets: move.source, toOffset: move.destination)
            expected.move(fromOffsets: IndexSet(integer: from), toOffset: to)
            #expect(all.filter(subset.contains) == expected)
            // Grouped batteries keep their relative order.
            #expect(all.filter { !subset.contains($0) } == [ids[1], ids[3]])
        }
        #expect(BatteryGroup.moveOffsets(of: [UUID()], in: ids, from: IndexSet(integer: 0), to: 1) == nil)
    }

    @Test @MainActor func batteryBelongsToOneGroupOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "groups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "groups.json")
        let shared = BatteryGroup.Member(id: UUID(), name: "공용"), own = BatteryGroup.Member(id: UUID(), name: "전용")
        let store = BatteryGroupStore(fileURL: url)
        let flash = BatteryGroup(name: "플래시", members: [shared, own])
        try store.update(flash)
        // Saving the battery into another device moves it out of the first one.
        try store.update(BatteryGroup(name: "리모컨", members: [shared]))
        #expect(store.groups.map { $0.members.map(\.name) } == [["전용"], ["공용"]])
        // Editing a device keeps its own members.
        try store.update(store.groups[0])
        #expect(store.groups.map { $0.members.map(\.name) } == [["전용"], ["공용"]])

        // A device that loses its last battery is deleted with its replacement history.
        try store.update(BatteryGroup(name: "시계", members: [own]))
        #expect(store.groups.map(\.name) == ["리모컨", "시계"])

        // Files written before the rule may hold a battery twice: the first device keeps it.
        let legacy = [flash, BatteryGroup(name: "리모컨", members: [shared]), BatteryGroup(name: "시계", members: [own, .init(id: UUID(), name: "새것")])]
        try JSONEncoder().encode(legacy).write(to: url)
        #expect(BatteryGroupStore(fileURL: url).groups.map { $0.members.map(\.name) } == [["공용", "전용"], ["새것"]])
    }

    @Test("AC-5.2 progress counts against the check total")
    func progressUsesCheckTotal() {
        let now = Date()
        let present = RegisteredBattery(id: UUID(), name: "A", lastReading: BatteryReading(rawVoltage: 400, isCharging: false, reportedSize: .aa, chargeCount: 1), lastSeen: now)
        let other = RegisteredBattery(id: UUID(), name: "B", lastReading: BatteryReading(rawVoltage: 390, isCharging: false, reportedSize: .aa, chargeCount: 1), lastSeen: now)
        let deleted = BatteryGroup.Member(id: UUID(), name: "삭제됨")
        let group = BatteryGroup(name: "플래시", members: [.init(id: present.id, name: "A"), .init(id: other.id, name: "B"), deleted])

        let check = BatteryGroupCheck.start(for: group, registered: [present, other], at: now)
        #expect(check.total == 2)
        #expect(check.excludedCount == 1)
        #expect(check.receivedCount == 2)
        #expect(!check.isWaiting)
        // The check still belongs to the device's full member list, deleted member included.
        #expect(check.belongs(to: group))
        #expect(!check.belongs(to: BatteryGroup(name: "플래시", members: Array(group.members.prefix(2)))))
    }
}

