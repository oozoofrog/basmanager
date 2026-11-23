import ActivityKit
import SwiftUI
import WidgetKit

@main
struct ChargingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            details(context)
                .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    details(context)
                }
            } compactLeading: {
                statusIcon(context)
            } compactTrailing: {
                if let percent = context.state.percent, !context.isStale {
                    Text("\(percent)%").monospacedDigit()
                } else {
                    Text("–").accessibilityLabel("현재 잔량 없음")
                }
            } minimal: {
                statusIcon(context)
            }
        }
    }

    private func details(_ context: ActivityViewContext<ChargingActivityAttributes>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(context)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.batteryName).font(.headline)
                statusText(context).font(.subheadline)
                Text("마지막 수신 \(context.state.observedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let percent = context.state.percent {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(percent)%").font(.title3.monospacedDigit())
                    Text(context.isStale ? "마지막 잔량" : "추정 잔량")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusText(_ context: ActivityViewContext<ChargingActivityAttributes>) -> Text {
        if context.isStale { return Text("새 수신 없음") }
        return context.state.isCharging ? Text("충전 중") : Text("충전 중 아님")
    }

    private func statusIcon(_ context: ActivityViewContext<ChargingActivityAttributes>) -> some View {
        let symbol = context.isStale ? "exclamationmark.circle" : (context.state.isCharging ? "bolt.fill" : "battery.50percent")
        return Image(systemName: symbol)
            .accessibilityLabel(statusText(context))
    }
}
