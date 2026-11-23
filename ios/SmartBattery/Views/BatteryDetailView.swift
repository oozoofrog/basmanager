import SwiftUI

struct BatteryDetailView: View {
    let id: UUID

    @Environment(BatteryStore.self) private var store
    @Environment(BatteryCentral.self) private var central
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sizeOverride: BatterySize?
    @State private var confirmsDelete = false
    @State private var showsFinder = false

    var body: some View {
        NavigationStack {
            if let battery = store.battery(id) {
                form(battery)
            } else {
                ContentUnavailableView("삭제된 배터리입니다", systemImage: "trash")
            }
        }
    }

    private func form(_ battery: RegisteredBattery) -> some View {
        Form {
            Section {
                BatteryRow(
                    name: battery.name,
                    reading: battery.lastReading,
                    size: store.effectiveSize(for: battery),
                    isOnline: store.isOnline(battery),
                    lastSeen: battery.lastSeen,
                    connection: store.connections[id]
                )
            }

            Section {
                Button("이 건전지 찾기", systemImage: "dot.radiowaves.left.and.right") { showsFinder = true }
                    .disabled(!store.isOnline(battery))
            } footer: {
                if !store.isOnline(battery) {
                    Text("건전지 신호가 수신될 때 찾을 수 있습니다.")
                }
            }

            Section("이름") {
                TextField("이름", text: $name)
            }

            Section {
                Picker("종류", selection: $sizeOverride) {
                    Text("자동 (\(battery.lastReading?.reportedSize.label ?? "–"))").tag(BatterySize?.none)
                    ForEach(BatterySize.allCases, id: \.self) { size in
                        Text(size.label).tag(BatterySize?.some(size))
                    }
                }
            } footer: {
                Text("잔량은 종류별 전압표로 계산해요. 건전지가 알려 주는 종류가 실제와 다르면 직접 선택하세요.")
            }

            Section {
                Toggle("계속 연결", isOn: Binding(
                    get: { battery.keepConnected },
                    set: { central.setKeepConnected($0, for: id) }
                ))
                LabeledContent("연결 상태", value: connectionText)
            } footer: {
                Text("켜 두면 앱이 열려 있는 동안 건전지에 연결해 1초마다 상태를 요청합니다. 연결하는 데 최대 20초 걸려요.")
            }

            Section {
                NavigationLink {
                    DiagnosticView(id: id, name: battery.name)
                } label: {
                    Label("고유 ID 진단", systemImage: "stethoscope")
                }
            } footer: {
                Text("건전지의 블루투스 정보를 읽어 연결 문제를 진단할 때 사용합니다.")
            }

            if let reading = battery.lastReading {
                Section("진단 정보") {
                    LabeledContent("전압 측정값", value: "\(reading.rawVoltage)")
                    if let seen = battery.lastSeen {
                        LabeledContent("마지막 수신", value: seen.formatted(date: .abbreviated, time: .standard))
                    }
                    if let rssi = store.sightings[id]?.rssi, rssi != 0 {
                        LabeledContent("신호 세기", value: "\(rssi) dBm")
                    }
                }
            }

            Section {
                Button("배터리 삭제", role: .destructive) { confirmsDelete = true }
            }
        }
        .navigationTitle(battery.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") { save(battery) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showsFinder) {
            FindBatteryView(id: id, name: battery.name)
        }
        .confirmationDialog("건전지를 삭제할까요?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                central.forget(id)
                dismiss()
            }
        } message: {
            Text("‘\(battery.name)’ 등록을 삭제할까요? 이 건전지의 충전 기록도 함께 지워집니다.")
        }
        .onAppear {
            name = battery.name
            sizeOverride = battery.sizeOverride
        }
    }

    private var connectionText: String {
        switch store.connections[id] {
        case .connected: String(localized: "연결됨")
        case .connecting: String(localized: "연결하는 중")
        case .failed: String(localized: "연결하지 못했어요")
        case .disconnected, nil: String(localized: "연결 안 됨")
        }
    }

    private func save(_ battery: RegisteredBattery) {
        var updated = battery
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sizeOverride = sizeOverride
        store.update(updated)
        dismiss()
    }
}
