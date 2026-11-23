import SwiftUI

struct BatteryRow: View {
    @Environment(\.lowBatteryThreshold) private var lowThreshold
    let name: String
    let reading: BatteryReading?
    let size: BatterySize?
    let isOnline: Bool
    let lastSeen: Date?
    let connection: ConnectionStatus?
    var signal: Int? = nil

    private var percent: Int? {
        guard let reading, let size else { return nil }
        return CapacityTable.percent(rawVoltage: reading.rawVoltage, size: size)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: BatteryLevel.symbol(percent: percent, charging: reading?.isCharging == true, threshold: lowThreshold))
                .font(.title2)
                .foregroundStyle(BatteryLevel.color(percent: percent, threshold: lowThreshold))
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.headline).lineLimit(1)
                    if let size {
                        Text(size.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 5)
                            .background(.quaternary, in: .capsule)
                    }
                    if connection == .connected {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("연결됨")
                    }
                }
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let percent {
                Text("\(percent)%")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BatteryLevel.color(percent: percent, threshold: lowThreshold))
            } else {
                Text("–").foregroundStyle(.secondary)
            }
        }
        .opacity(isOnline ? 1 : 0.55)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        var parts: [String] = []
        if reading?.isCharging == true {
            parts.append(String(localized: "충전 중"))
        }
        if let count = reading?.chargeCount {
            parts.append(String(localized: "충전 \(count)회"))
        }
        if case .connecting = connection {
            parts.append(String(localized: "연결하는 중"))
        } else if isOnline {
            parts.append(String(localized: "수신 중"))
        } else if let lastSeen {
            parts.append(String(localized: "대기 · \(lastSeen.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "대기"))
        }
        if let signal, signal != 0 {
            parts.append("\(signal) dBm")
        }
        return parts.joined(separator: " · ")
    }
}

/// Level buckets: ≥80, ≥50, ≥ low threshold, below the low threshold (ADR-0001, decision 2).
enum BatteryLevel {
    static func symbol(percent: Int?, charging: Bool, threshold: Int) -> String {
        if charging { return "battery.100percent.bolt" }
        guard let percent else { return "battery.0percent" }
        if percent >= 80 { return "battery.100percent" }
        if percent >= 50 { return "battery.75percent" }
        if percent >= threshold { return "battery.50percent" }
        return "battery.25percent"
    }

    static func color(percent: Int?, threshold: Int) -> Color {
        guard let percent else { return .secondary }
        if percent >= 50 { return .green }
        if percent >= threshold { return .orange }
        return .red
    }
}
