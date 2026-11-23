import CoreBluetooth
import SwiftUI

struct BatteryListView: View {
    @Environment(BatteryStore.self) private var store
    @Environment(BatteryCentral.self) private var central
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.lowBatteryThreshold) private var lowThreshold
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var groups: BatteryGroupStore
    /// Running or finished device checks, keyed by group ID.
    @State private var checks: [UUID: BatteryGroupCheck] = [:]
    @State private var managing: UUID?
    @State private var addsGroup = false

    @State private var registering: UUID?
    @State private var editing: UUID?
    @State private var pendingDelete: RegisteredBattery?
    @State private var showsSettings = false
    @State private var showsLimitAlert = false

    init(groups: BatteryGroupStore = BatteryGroupStore()) {
        _groups = State(initialValue: groups)
    }

    var body: some View {
        NavigationStack {
            List {
                if store.batteryLoadFailed {
                    batteryLoadFailedSection
                }
                if central.state != .poweredOn {
                    bluetoothSection
                }
                if !store.batteryLoadFailed {
                    chargingSection
                }
                Section {
                    NavigationLink {
                        ChargingDashboardView()
                    } label: {
                        Label("충전 현황과 기록", systemImage: "bolt.batteryblock")
                    }
                    if groups.loadFailed {
                        Label("장비 목록을 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                    } else if !store.registered.isEmpty, !store.batteryLoadFailed {
                        Button("장비 추가", systemImage: "square.stack.3d.up") { addsGroup = true }
                    }
                } footer: {
                    if !groups.loadFailed, !store.registered.isEmpty, groups.groups.isEmpty {
                        Text("건전지를 장비별로 묶으면 이 목록에서 장비 단위로 점검할 수 있어요.")
                    }
                }
                ForEach(groups.groups) { group in
                    groupSection(group)
                }
                ungroupedSection
                if !store.batteryLoadFailed {
                    unregisteredSection
                }
                if !store.batteryLoadFailed, store.registered.isEmpty, store.unregistered.isEmpty, central.state == .poweredOn {
                    Section {
                        ContentUnavailableView {
                            Label("주변에서 찾은 건전지가 없어요", systemImage: "antenna.radiowaves.left.and.right")
                        } description: {
                            Text("건전지를 iPhone 가까이 두면 미등록 목록에 나타납니다.")
                        }
                    }
                }
            }
            .navigationTitle("Basmanager")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("설정", systemImage: "gearshape") { showsSettings = true }
                }
                if !store.batteryLoadFailed, ungrouped.count > 1 || groups.groups.contains(where: { $0.members.count > 1 }) {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
            .sheet(item: $registering) { id in
                RegisterSheet(id: id)
            }
            .sheet(item: $editing) { id in
                BatteryDetailView(id: id)
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView(groups: groups)
            }
            .sheet(item: $managing) { id in
                BatteryGroupManageView(groupID: id, groups: groups)
            }
            .sheet(isPresented: $addsGroup) {
                BatteryGroupEditor(group: BatteryGroup(), groups: groups)
            }
            .onChange(of: store.registered) { observeChecks() }
            .onChange(of: store.now) { observeChecks() }
            .onChange(of: central.state) { _, state in
                if state != .poweredOn { cancelChecks() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { cancelChecks() }
            }
            .onChange(of: groups.groups) { _, updated in
                // A check belongs to the member set it started with.
                checks = checks.filter { id, check in
                    updated.first { $0.id == id }.map(check.belongs(to:)) ?? false
                }
            }
            .confirmationDialog(
                "건전지를 삭제할까요?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { battery in
                Button("삭제", role: .destructive) { central.forget(battery.id) }
            } message: { battery in
                Text("\(battery.name) 건전지와 충전 기록을 삭제해요. 이 건전지가 들어 있는 장비에는 등록이 삭제된 건전지로 표시돼요.")
            }
            .alert("더 등록할 수 없어요", isPresented: $showsLimitAlert) {
                Button("확인") {}
            } message: {
                Text("건전지는 \(BatteryProtocol.registrationLimit)개까지 등록할 수 있어요.")
            }
        }
    }

    private var batteryLoadFailedSection: some View {
        Section {
            Label("건전지 목록을 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(BatteryStore.loadFailureNextAction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bluetoothSection: some View {
        Section {
            switch central.state {
            case .unauthorized:
                Label("블루투스 사용 권한이 없습니다", systemImage: "exclamationmark.triangle")
                Button("설정에서 권한 허용") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .poweredOff:
                Label("블루투스가 꺼져 있습니다. 제어 센터나 설정에서 켜 주세요.", systemImage: "bolt.horizontal.circle")
            case .unsupported:
                Label("이 기기는 Bluetooth LE를 지원하지 않습니다", systemImage: "xmark.octagon")
            default:
                Label("블루투스 준비 중", systemImage: "hourglass")
            }
        }
    }

    @ViewBuilder
    private var chargingSection: some View {
        let ids = store.recentlyStartedCharging.filter { store.sightings[$0] != nil }
        if !ids.isEmpty {
            Section {
                ForEach(ids, id: \.self) { id in
                    let battery = store.battery(id)
                    let sighting = store.sightings[id]
                    Button {
                        if battery != nil {
                            editing = id
                        } else if store.canRegisterMore {
                            registering = id
                        } else {
                            showsLimitAlert = true
                        }
                    } label: {
                        BatteryRow(
                            name: battery?.name ?? String(localized: "미등록"),
                            reading: sighting?.reading,
                            size: battery.flatMap(store.effectiveSize(for:)) ?? sighting?.reading.reportedSize,
                            isOnline: true,
                            lastSeen: sighting?.lastSeen,
                            connection: store.connections[id]
                        )
                    }
                    .tint(.primary)
                }
            } header: {
                Label("방금 충전을 시작한 건전지", systemImage: "bolt.fill")
                    .foregroundStyle(.green)
            } footer: {
                Text("충전기에 꽂은 건전지가 1분 동안 여기에 표시됩니다.")
            }
        }
    }

    private var ungrouped: [RegisteredBattery] {
        BatteryGroup.ungrouped(store.registered, in: groups.groups)
    }

    private func registeredRow(_ battery: RegisteredBattery, status: BatteryGroupCheckStatus? = nil) -> some View {
        Button { editing = battery.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                BatteryRow(
                    name: battery.name,
                    reading: battery.lastReading,
                    size: store.effectiveSize(for: battery),
                    isOnline: store.isOnline(battery),
                    lastSeen: battery.lastSeen,
                    connection: store.connections[battery.id]
                )
                if let status {
                    HStack(spacing: 6) {
                        Image(systemName: status.symbol)
                            .symbolEffect(.variableColor.iterative, isActive: status == .waiting && !reduceMotion)
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .accessibilityHidden(true)
                        Text(status.title)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .animation(reduceMotion ? nil : .default, value: status)
                    .padding(.leading, 58)
                    .padding(.bottom, 4)
                }
            }
        }
        .tint(.primary)
        .swipeActions {
            Button("삭제", systemImage: "trash", role: .destructive) { pendingDelete = battery }
        }
    }

    private func groupSection(_ group: BatteryGroup) -> some View {
        let check = checks[group.id]
        let hasRegisteredMembers = group.members.contains { store.battery($0.id) != nil }
        return Section {
            ForEach(group.members) { member in
                if let battery = store.battery(member.id) {
                    registeredRow(battery, status: check.map {
                        BatteryGroupCheckStatus(sample: $0.samples[member.id], isWaiting: $0.isWaiting, lowThreshold: lowThreshold)
                    })
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name)
                        Text(store.batteryLoadFailed ? "불러오지 못함" : "등록 삭제됨").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { source, destination in
                guard !store.batteryLoadFailed else { return }
                var updated = group
                updated.members.move(fromOffsets: source, toOffset: destination)
                // On a failed save the store keeps the old order, which the list then shows again.
                try? groups.update(updated)
            }
        } header: {
            HStack(spacing: 16) {
                Text(group.name)
                Spacer()
                if let check {
                    CheckProgressRing(received: check.receivedCount, total: check.total, reduceMotion: reduceMotion)
                }
                if check?.isWaiting == true {
                    Button("중단") { checks[group.id]?.cancel(at: .now) }
                } else {
                    Button("점검") { startCheck(group) }
                        .disabled(store.batteryLoadFailed)
                        .disabled(central.state != .poweredOn || !hasRegisteredMembers)
                        .accessibilityLabel("\(group.name) 점검")
                }
                Button("\(group.name) 관리", systemImage: "ellipsis.circle") { managing = group.id }
                    .disabled(store.batteryLoadFailed)
                    .labelStyle(.iconOnly)
            }
        } footer: {
            let lines = footerLines(group, check: check)
            if !lines.isEmpty {
                Text(lines.joined(separator: "\n"))
            }
        }
    }

    private func footerLines(_ group: BatteryGroup, check: BatteryGroupCheck?) -> [String] {
        var lines: [String] = []
        if let check {
            let received: [(name: String, percent: Int)] = group.members.compactMap { member in
                guard let battery = store.battery(member.id), let sample = check.samples[member.id] else { return nil }
                return (battery.name, sample.percent)
            }
            if check.isWaiting {
                lines.append(String(localized: "점검 중: \(check.total)개 중 \(check.receivedCount)개 수신 (최대 \(BatteryGroupCheck.timeout)초)"))
            } else {
                let seconds = (check.duration ?? 0).formatted(.number.precision(.fractionLength(0...1)))
                lines.append(check.wasCancelled
                    ? String(localized: "점검 중단: \(check.total)개 중 \(check.receivedCount)개 수신")
                    : String(localized: "점검 결과: \(check.total)개 중 \(check.receivedCount)개 수신 · \(seconds)초"))
            }
            if check.excludedCount > 0 {
                lines.append(String(localized: "삭제된 건전지 \(check.excludedCount)개 제외"))
            }
            if let lowest = received.min(by: { $0.percent < $1.percent }) {
                lines.append(String(localized: "가장 낮은 추정 잔량: \(lowest.name) \(lowest.percent)%"))
            }
        }
        if let days = group.daysSinceReplacement() {
            lines.append(days == 0 ? String(localized: "오늘 교체했어요") : String(localized: "지난 교체 후 \(days)일"))
        }
        return lines
    }

    @ViewBuilder
    private var ungroupedSection: some View {
        let batteries = ungrouped
        if !batteries.isEmpty {
            Section(groups.groups.isEmpty ? "등록 \(batteries.count)개" : "장비 미지정 \(batteries.count)개") {
                ForEach(batteries) { battery in
                    registeredRow(battery)
                }
                .onMove { source, destination in
                    guard let move = BatteryGroup.moveOffsets(
                        of: batteries.map(\.id), in: store.registered.map(\.id), from: source, to: destination
                    ) else { return }
                    store.move(from: move.source, to: move.destination)
                }
            }
        }
    }

    private func startCheck(_ group: BatteryGroup) {
        checks[group.id] = BatteryGroupCheck.start(for: group, registered: store.registered, at: .now)
    }

    /// Runs on every reading and on the store's one-second tick, which also ends timed-out checks.
    private func observeChecks() {
        for id in checks.keys where checks[id]?.isWaiting == true {
            checks[id]?.observe(store.registered, at: .now)
        }
    }

    private func cancelChecks() {
        for id in checks.keys { checks[id]?.cancel(at: .now) }
    }

    @ViewBuilder
    private var unregisteredSection: some View {
        let found = store.unregistered
        if !found.isEmpty {
            Section {
                ForEach(found, id: \.id) { item in
                    Button {
                        if store.canRegisterMore { registering = item.id } else { showsLimitAlert = true }
                    } label: {
                        BatteryRow(
                            name: String(localized: "미등록"),
                            reading: item.sighting.reading,
                            size: item.sighting.reading.reportedSize,
                            isOnline: true,
                            lastSeen: item.sighting.lastSeen,
                            connection: nil,
                            signal: item.sighting.rssi
                        )
                    }
                    .tint(.primary)
                }
            } header: {
                Text("미등록 \(found.count)개")
            } footer: {
                Text("가까운 순서로 표시됩니다. 어느 건전지인지 모르면 충전기에 꽂으세요. 충전을 시작한 건전지가 맨 위에 표시됩니다.")
            }
        }
    }
}

#Preview("파일 오류") {
    let folder = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let batteryURL = folder.appending(path: "registered-batteries.json")
    try? Data("not json".utf8).write(to: batteryURL)
    let store = BatteryStore(fileURL: batteryURL)
    store.record(BatteryReading(rawVoltage: 390, isCharging: false, reportedSize: .aa, chargeCount: 4), rssi: -60, from: UUID())
    let groups = BatteryGroupStore(fileURL: folder.appending(path: "battery-groups.json"))
    try? groups.update(BatteryGroup(name: "카메라 플래시", members: [.init(id: UUID(), name: "플래시 1")]))
    return BatteryListView(groups: groups)
        .environment(store)
        .environment(BatteryCentral(store: store))
        .environment(ChargingLiveActivityController())
}

/// Received/check-total progress for a device check. It changes without animation when Reduce Motion is on.
private struct CheckProgressRing: View {
    let received: Int
    let total: Int
    let reduceMotion: Bool

    private var fraction: Double { total == 0 ? 0 : Double(received) / Double(total) }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(fraction >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("\(total)개 중 \(received)개 수신")
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

#Preview("장비 섹션") {
    let folder = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = BatteryStore(fileURL: nil)
    let groups = BatteryGroupStore(fileURL: folder.appending(path: "groups.json"))
    var ids: [UUID] = []
    for (name, voltage, size) in [("플래시 1", 400, BatterySize.aa), ("플래시 2", 345, .aa), ("리모컨", 380, .aaa), ("도어락", 395, .aa)] {
        let id = UUID()
        ids.append(id)
        store.record(BatteryReading(rawVoltage: voltage, isCharging: false, reportedSize: size, chargeCount: 8), rssi: -60, from: id)
        store.register(id, name: name)
    }
    try? groups.update(BatteryGroup(
        name: "카메라 플래시",
        members: [.init(id: ids[0], name: "플래시 1"), .init(id: ids[1], name: "플래시 2"), .init(id: UUID(), name: "플래시 3")],
        replacements: [.init(date: .now.addingTimeInterval(-86_400 * 12))]
    ))
    return BatteryListView(groups: groups)
        .environment(store)
        .environment(BatteryCentral(store: store))
        .environment(ChargingLiveActivityController())
}
