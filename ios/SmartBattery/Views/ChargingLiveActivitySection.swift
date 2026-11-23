import ActivityKit
import SwiftUI

struct ChargingLiveActivitySection: View {
    @Environment(BatteryStore.self) private var store
    @Environment(ChargingLiveActivityController.self) private var controller
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if #available(iOS 26, *) {
                if let active = controller.active {
                    LabeledContent("표시 중인 건전지", value: active.attributes.batteryName)
                    Button("실시간 현황 종료", systemImage: "stop.circle") {
                        Task { await controller.stop() }
                    }
                    .disabled(controller.isStopping)
                } else if !controller.isEnabled {
                    Text("실시간 현황이 꺼져 있어요.")
                    Button("앱 설정 열기", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else {
                    let charging = store.registered.filter {
                        $0.lastReading?.isCharging == true && store.hasFreshReading(for: $0)
                    }
                    if charging.isEmpty {
                        Label("충전 중인 건전지를 아직 확인하지 못했어요.", systemImage: "lock")
                    } else {
                        Menu("잠금 화면에 표시", systemImage: "lock") {
                            ForEach(charging) { battery in
                                Button(battery.name) { controller.start(for: battery.id, in: store) }
                            }
                        }
                        .disabled(controller.isStopping)
                    }
                    if controller.startFailed {
                        Text("실시간 현황을 시작하지 못했어요. 충전 상태를 확인한 뒤 다시 시도해 주세요.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("잠금 화면 충전 현황은 iOS 26부터 지원해요.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("잠금 화면")
        } footer: {
            if #available(iOS 26, *), controller.active != nil {
                Text("화면이 꺼지면 새 수신이 늦어질 수 있어요.")
            }
        }
    }
}
