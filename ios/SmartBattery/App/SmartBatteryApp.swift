import SwiftUI

@main
struct SmartBatteryApp: App {
    @State private var store: BatteryStore
    @State private var central: BatteryCentral
    @State private var chargingActivity: ChargingLiveActivityController

    init() {
        let store = BatteryStore()
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
                .environment(store)
                .environment(central)
                .environment(chargingActivity)
        }
    }
}
