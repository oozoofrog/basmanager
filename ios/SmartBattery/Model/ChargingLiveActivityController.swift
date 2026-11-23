import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class ChargingLiveActivityController {
    private(set) var active: Activity<ChargingActivityAttributes>?
    private(set) var startFailed = false
    private(set) var isStopping = false

    @ObservationIgnored private var latest: ChargingActivityAttributes.ContentState?
    @ObservationIgnored private var pending: ChargingActivityAttributes.ContentState?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var activityStateTask: Task<Void, Never>?

    init() {
        if #available(iOS 26, *), let activity = Activity<ChargingActivityAttributes>.activities.first {
            observe(activity)
        }
    }

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(for id: UUID, in store: BatteryStore) {
        startFailed = false
        guard #available(iOS 26, *), active == nil, !isStopping else { return }
        guard isEnabled, let battery = store.battery(id),
              let state = snapshot(for: battery, in: store), state.isCharging else {
            startFailed = true
            return
        }

        do {
            let activity = try Activity.request(
                attributes: ChargingActivityAttributes(batteryID: id, batteryName: battery.name),
                content: content(for: state)
            )
            observe(activity)
        } catch {
            startFailed = true
        }
    }

    func receivedReading(in store: BatteryStore) {
        guard #available(iOS 26, *), let activity = active, !isStopping,
              let battery = store.battery(activity.attributes.batteryID),
              let state = snapshot(for: battery, in: store), let latest,
              state.observedAt > latest.observedAt else { return }

        let interval: TimeInterval = state.percent == latest.percent ? 10 : 3
        guard state.isCharging != latest.isCharging || state.observedAt.timeIntervalSince(latest.observedAt) >= interval
        else { return }

        self.latest = state
        pending = state
        guard updateTask == nil else { return }
        let activityID = activity.id
        updateTask = Task { [weak self] in
            while let self, active?.id == activityID, !isStopping, let state = pending {
                pending = nil
                await Self.publish(content(for: state), at: state.observedAt, to: activityID)
            }
            if self?.active?.id == activityID { self?.updateTask = nil }
        }
    }

    func stop() async {
        guard let activityID = active?.id, !isStopping else { return }
        isStopping = true
        await Self.endActivity(activityID)
        if active?.id == activityID { clear() }
        isStopping = false
    }

    @available(iOS 18.0, *)
    private nonisolated static func publish(
        _ content: ActivityContent<ChargingActivityAttributes.ContentState>, at timestamp: Date, to id: String
    ) async {
        let activity = Activity<ChargingActivityAttributes>.activities.first { $0.id == id }
        await activity?.update(content, timestamp: timestamp)
    }

    private nonisolated static func endActivity(_ id: String) async {
        let activity = Activity<ChargingActivityAttributes>.activities.first { $0.id == id }
        await activity?.end(nil, dismissalPolicy: .immediate)
    }

    private func snapshot(for battery: RegisteredBattery, in store: BatteryStore) -> ChargingActivityAttributes.ContentState? {
        guard store.hasFreshReading(for: battery), let reading = battery.lastReading,
              let observedAt = battery.lastSeen else { return nil }
        return .init(isCharging: reading.isCharging, percent: store.percent(for: battery), observedAt: observedAt)
    }

    private func content(for state: ChargingActivityAttributes.ContentState) -> ActivityContent<ChargingActivityAttributes.ContentState> {
        .init(state: state, staleDate: state.observedAt.addingTimeInterval(BatteryProtocol.offlineInterval))
    }

    private func observe(_ activity: Activity<ChargingActivityAttributes>) {
        active = activity
        latest = activity.content.state
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard self?.active?.id == activity.id else { break }
                if state == .ended || state == .dismissed {
                    self?.clear()
                    break
                }
            }
        }
    }

    private func clear() {
        activityStateTask?.cancel()
        activityStateTask = nil
        updateTask?.cancel()
        updateTask = nil
        pending = nil
        latest = nil
        active = nil
    }
}
