import SwiftUI

@main
struct SmartBatteryApp: App {
    @State private var store: BatteryStore
    @AppStorage(LowBatteryThreshold.key) private var lowThreshold = LowBatteryThreshold.defaultValue
    @State private var central: BatteryCentral
    @State private var chargingActivity: ChargingLiveActivityController

    init() {
        let store = BatteryStore.onDevice()
        let chargingActivity = ChargingLiveActivityController()
        store.onReading = { [weak store, weak chargingActivity] in
            guard let store else { return }
            chargingActivity?.receivedReading(in: store)
        }
        _store = State(initialValue: store)
        _central = State(initialValue: BatteryCentral(store: store))
        _chargingActivity = State(initialValue: chargingActivity)
    }

    var body: some Scene {
        WindowGroup {
            BatteryListView()
                .chargeGoalAlerts()
                .environment(\.lowBatteryThreshold, LowBatteryThreshold.normalized(lowThreshold))
                .environment(store)
                .environment(central)
                .environment(chargingActivity)
        }
    }
}
