import SwiftUI

/// Collects raw advertisement and read-only GATT values so a cross-device battery identifier can be found.
struct DiagnosticView: View {
    let id: UUID
    let name: String

    @Environment(BatteryCentral.self) private var central
    @Environment(BatteryStore.self) private var store

    private var report: ProbeReport? { central.probeReports[id] }
    private var isRunning: Bool { report != nil && report?.finished == false }

    private var reportText: String {
        var lines = ["Basmanager diagnostic", "battery: \(name)"]
        if let reading = store.battery(id)?.lastReading {
            lines.append("reading: voltage=\(reading.rawVoltage) size=\(reading.reportedSize.label) charging=\(reading.isCharging) count=\(reading.chargeCount.map(String.init) ?? "none")")
        }
        lines += report?.lines ?? []
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Button {
                    central.probe(id)
                } label: {
                    if isRunning {
                        Label("진단 중…", systemImage: "hourglass")
                    } else {
                        Label(report == nil ? "진단 시작" : "다시 진단", systemImage: "stethoscope")
                    }
                }
                .disabled(isRunning || central.state != .poweredOn || store.battery(id).map(store.isOnline) != true)
            } footer: {
                Text("건전지에 연결해 블루투스 정보를 읽기만 합니다. 건전지 설정은 바꾸지 않습니다. 25초 안에 끝납니다.")
            }

            if report != nil {
                Section {
                    ShareLink(item: reportText) {
                        Label("결과 공유", systemImage: "square.and.arrow.up")
                    }
                    Button("결과 복사", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = reportText
                    }
                }
                Section("결과") {
                    Text(reportText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("고유 ID 진단")
        .navigationBarTitleDisplayMode(.inline)
    }
}
