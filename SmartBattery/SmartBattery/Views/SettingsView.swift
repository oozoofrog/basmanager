import SwiftUI

struct SettingsView: View {
    let groups: BatteryGroupStore

    @Environment(BatteryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LowBatteryThreshold.key) private var storedThreshold = LowBatteryThreshold.defaultValue

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("버전", value: version)
                }

                savedDataSection

                Section {
                    Stepper(
                        value: Binding(
                            get: { LowBatteryThreshold.normalized(storedThreshold) },
                            set: { storedThreshold = LowBatteryThreshold.normalized($0) }
                        ),
                        in: LowBatteryThreshold.range,
                        step: LowBatteryThreshold.step
                    ) {
                        LabeledContent("잔량 낮음 기준", value: "\(LowBatteryThreshold.normalized(storedThreshold))%")
                    }
                } footer: {
                    Text("추정 잔량이 이 값보다 낮으면 목록에 빨간색으로 표시하고, 장비 점검에서 잔량 낮음으로 알려요.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var savedDataSection: some View {
        Section {
            if store.batteryLoadFailed {
                failureRow("건전지 목록을 불러오지 못했어요")
            } else {
                LabeledContent("등록한 건전지", value: "\(store.registered.count)개")
            }
            if groups.loadFailed {
                failureRow("장비 목록을 불러오지 못했어요")
            } else {
                LabeledContent("장비", value: "\(groups.groups.count)개")
            }
            if store.chargingLoadFailed {
                failureRow("충전 기록을 불러오지 못했어요")
            } else {
                LabeledContent("충전 기록", value: "\(store.chargeHistory.count)개")
            }
            if store.chargingSaveFailed {
                Label("충전 기록을 저장하지 못했어요", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("다시 저장") { store.retrySavingCharging() }
            }
        } header: {
            Text("저장된 데이터")
        } footer: {
            if store.batteryLoadFailed || store.chargingLoadFailed || groups.loadFailed {
                Text(BatteryStore.loadFailureNextAction)
            } else {
                Text("이 정보는 이 iPhone에만 저장하고 어디로도 보내지 않아요. iPhone 백업에는 포함될 수 있어요. 다른 iPhone에서는 건전지를 다시 등록해야 해요.")
            }
        }
    }

    private func failureRow(_ title: LocalizedStringKey) -> some View {
        Label(title, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
    }
}

#Preview("설정") {
    let folder = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = BatteryStore(fileURL: nil)
    let id = UUID()
    store.record(BatteryReading(rawVoltage: 390, isCharging: true, reportedSize: .aa, chargeCount: 4), rssi: -60, from: id)
    store.register(id, name: "도어락")
    let groups = BatteryGroupStore(fileURL: folder.appending(path: "battery-groups.json"))
    return SettingsView(groups: groups).environment(store)
}

