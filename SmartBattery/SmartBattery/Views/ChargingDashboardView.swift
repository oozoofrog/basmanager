import SwiftUI

struct ChargingDashboardView: View {
    @Environment(BatteryStore.self) private var store
    @State private var selectedIDs: Set<UUID> = []

    private var chargingBatteries: [RegisteredBattery] {
        store.registered.filter { $0.lastReading?.isCharging == true }
    }

    var body: some View {
        List {
            if store.batteryLoadFailed {
                Section {
                    Label("건전지 목록을 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(BatteryStore.loadFailureNextAction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if store.chargingLoadFailed {
                Section {
                    Label("충전 기록을 불러오지 못했어요", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(BatteryStore.loadFailureNextAction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if store.chargingSaveFailed {
                Section {
                    Text("충전 설정과 기록을 저장하지 못했어요.")
                    Button("다시 저장") { store.retrySavingCharging() }
                }
            }
            chargingSection
            goalSection
            ChargingLiveActivitySection()
            historySection
        }
        .navigationTitle("충전")
        .onChange(of: store.registered.map(\.id), initial: true) { _, ids in
            selectedIDs.formIntersection(ids)
            if selectedIDs.isEmpty, ids.count == 1 {
                selectedIDs = Set(ids)
            }
        }
    }

    private var chargingSection: some View {
        Section("충전 상태") {
            if chargingBatteries.isEmpty {
                Text("아직 충전 중인 건전지가 확인되지 않았어요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(chargingBatteries) { battery in
                let fresh = store.hasFreshReading(for: battery)
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent {
                        if let percent = store.percent(for: battery) {
                            Text(fresh ? "추정 \(percent)%" : "마지막 추정 \(percent)%")
                        }
                    } label: {
                        Text(battery.name)
                    }
                    Text(fresh ? "충전 중" : "수신 대기 · 마지막 상태는 충전 중")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let seen = battery.lastSeen {
                        Text("마지막 수신 \(seen.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var goalSection: some View {
        Section {
            if store.batteryLoadFailed {
                Text("건전지 목록을 불러온 뒤에 목표를 설정할 수 있어요.")
                    .foregroundStyle(.secondary)
            } else if store.registered.isEmpty {
                Text("목표를 설정하려면 건전지를 먼저 등록해 주세요.")
                    .foregroundStyle(.secondary)
            } else if store.monitoredChargeIDs.isEmpty {
                Stepper(
                    "목표 추정 잔량 \(store.chargeGoal)%",
                    value: Binding(get: { store.chargeGoal }, set: { store.setChargeGoal($0) }),
                    in: BatteryStore.chargeGoalRange,
                    step: 5
                )
                .disabled(store.chargingLoadFailed || store.batteryLoadFailed)
                ForEach(store.registered) { battery in
                    Button {
                        if selectedIDs.contains(battery.id) {
                            selectedIDs.remove(battery.id)
                        } else {
                            selectedIDs.insert(battery.id)
                        }
                    } label: {
                        HStack {
                            Text(battery.name)
                            Spacer()
                            Image(systemName: selectedIDs.contains(battery.id) ? "checkmark.circle.fill" : "circle")
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityAddTraits(selectedIDs.contains(battery.id) ? .isSelected : [])
                }
                Button("목표 확인 시작") { store.startChargeGoalMonitoring(for: selectedIDs) }
                    .disabled(selectedIDs.isEmpty)
            } else {
                Text("목표 추정 잔량 \(store.chargeGoal)%")
                ForEach(store.registered.filter { store.monitoredChargeIDs.contains($0.id) }) { battery in
                    let reached = store.reachedChargeGoalIDs.contains(battery.id)
                    LabeledContent {
                        Text(reached ? "목표 확인" : "확인 대기")
                    } label: {
                        Text(battery.name)
                    }
                }
                Button("목표 확인 중지") { store.stopChargeGoalMonitoring() }
            }
        } header: {
            Text("목표 잔량 알림")
        } footer: {
            if !store.registered.isEmpty {
                Text("충전 중인 건전지에서 목표 이상을 새로 수신하면 앱에서 알려드려요.")
            }
        }
    }

    private var historySection: some View {
        Section("최근 충전 기록") {
            if store.chargeHistory.isEmpty {
                Text("기록이 없어요.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.chargeHistory.reversed().sorted { $0.date > $1.date }) { event in
                if let battery = store.battery(event.batteryID) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(battery.name)
                        Text(event.kind.title)
                            .font(.subheadline)
                        Text(event.date, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let percent = event.percent {
                            Text("추정 \(percent)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let count = event.chargeCount {
                            Text("건전지가 보고한 충전 횟수 \(count)회")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private extension ChargeObservation.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .started: "충전 시작 감지"
        case .alreadyCharging: "충전 중 신호 수신"
        case .chargingSignalEnded: "충전 중 신호 종료"
        case .receptionInterrupted: "수신 끊김 · 마지막 충전 신호"
        }
    }
}

extension View {
    func chargeGoalAlerts() -> some View {
        modifier(ChargeGoalAlertsModifier())
    }
}

private struct ChargeGoalAlertsModifier: ViewModifier {
    @Environment(BatteryStore.self) private var store

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = store.chargeGoalNotices.first {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(notice.batteryName) · 목표 잔량 확인")
                            .font(.headline)
                        Text("추정 \(notice.percent)% · 목표 \(notice.goal)%")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 12)
                    Button("확인") { store.dismissChargeGoalNotice(notice.id) }
                        .buttonStyle(.bordered)
                }
                .padding()
                .background(.regularMaterial)
            }
        }
    }
}
