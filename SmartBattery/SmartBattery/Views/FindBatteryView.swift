import SwiftUI

/// Signal-strength finder. BLE RSSI gives only "closer / farther", not a distance or direction.
struct FindBatteryView: View {
    let id: UUID
    let name: String

    @Environment(BatteryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Exponential moving average of RSSI; raw values jump by several dB between packets.
    @State private var smoothed: Double?
    @State private var lastSample: Date?

    private var sighting: Sighting? { store.sightings[id] }

    private var proximity: Proximity? {
        guard let smoothed, let sighting, store.isOnline(sighting.lastSeen) else { return nil }
        return Proximity(rssi: smoothed)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                gauge
                VStack(spacing: 6) {
                    Text(proximity?.title ?? String(localized: "신호 없음"))
                        .font(.largeTitle.weight(.bold))
                    Text(detailText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("iPhone을 들고 천천히 움직이세요. 신호가 강해지는 쪽에 건전지가 있습니다. 벽, 금속 케이스, 몸에 가리면 신호가 약해질 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("\(name) 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .sensoryFeedback(trigger: proximity) { old, new in
                guard let old, let new else { return nil }
                return new > old ? .increase : (new < old ? .decrease : nil)
            }
            .onAppear { sample(sighting) }
            .onChange(of: sighting) { _, new in sample(new) }
        }
    }

    private var gauge: some View {
        let fraction = proximity == nil ? 0 : Proximity.fraction(rssi: smoothed ?? -100)
        let color = proximity?.color ?? .secondary
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 22)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            Image(systemName: "battery.100percent")
                .font(.system(size: 64))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: proximity == .veryClose)
        }
        .frame(width: 240, height: 240)
        .accessibilityElement()
        .accessibilityLabel(proximity?.title ?? String(localized: "신호 없음"))
    }

    private var detailText: String {
        guard let sighting, let smoothed, store.isOnline(sighting.lastSeen) else {
            return String(localized: "35초 넘게 수신되지 않았습니다. 건전지가 범위 밖이거나 꺼져 있을 수 있습니다.")
        }
        let age = max(0, Int(store.now.timeIntervalSince(sighting.lastSeen)))
        return String(localized: "\(Int(smoothed.rounded())) dBm · \(age)초 전 수신")
    }

    private func sample(_ sighting: Sighting?) {
        guard let sighting, sighting.rssi != 0, sighting.lastSeen != lastSample else { return }
        lastSample = sighting.lastSeen
        let value = Double(sighting.rssi)
        smoothed = smoothed.map { $0 * 0.7 + value * 0.3 } ?? value
    }
}

enum Proximity: Int, Comparable {
    case far, near, close, veryClose

    /// Thresholds are rough rules of thumb for a phone-to-battery link; real values vary by device and enclosure.
    init(rssi: Double) {
        if rssi >= -55 {
            self = .veryClose
        } else if rssi >= -67 {
            self = .close
        } else if rssi >= -80 {
            self = .near
        } else {
            self = .far
        }
    }

    static func fraction(rssi: Double) -> Double {
        min(1, max(0.04, (rssi + 100) / 60))
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .veryClose: String(localized: "바로 옆")
        case .close: String(localized: "가까움")
        case .near: String(localized: "보통 거리")
        case .far: String(localized: "멀리 있음")
        }
    }

    var color: Color {
        switch self {
        case .veryClose: .green
        case .close: .mint
        case .near: .orange
        case .far: .red
        }
    }
}
