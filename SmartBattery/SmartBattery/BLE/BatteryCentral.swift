@preconcurrency import CoreBluetooth
import Foundation
import Observation

/// Read-only GATT dump used to look for a battery identifier that is stable across iPhones.
struct ProbeReport: Equatable, Sendable {
    var lines: [String]
    var finished: Bool
}

/// Scans Smart15V advertisements and keeps optional UART connections:
/// scan with service AF30 and duplicates, then poll connected batteries with `E1 05 00 02` every second.
@MainActor
@Observable
final class BatteryCentral: NSObject {
    private(set) var state: CBManagerState = .unknown
    /// Latest raw advertisement per battery, for diagnostics.
    private(set) var advertisements: [UUID: String] = [:]
    private(set) var probeReports: [UUID: ProbeReport] = [:]

    @ObservationIgnored private let store: BatteryStore
    @ObservationIgnored private var manager: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var writeCharacteristics: [UUID: CBCharacteristic] = [:]
    @ObservationIgnored private var missedResponses: [UUID: Int] = [:]
    @ObservationIgnored private var probeStarted: [UUID: Date] = [:]
    @ObservationIgnored private var pendingProbeWork: [UUID: Int] = [:]
    @ObservationIgnored private var timer: Timer?

    /// A connection is dropped after four ticks without fresh data.
    private let maxMissedResponses = 4
    private let connectTimeout: TimeInterval = 20
    private let probeTimeout: TimeInterval = 25
    private let uartService = CBUUID(string: BatteryProtocol.uartServiceUUID)
    private let uartWrite = CBUUID(string: BatteryProtocol.uartWriteUUID)
    private let uartNotify = CBUUID(string: BatteryProtocol.uartNotifyUUID)

    init(store: BatteryStore) {
        self.store = store
        super.init()
        manager = CBCentralManager(delegate: self, queue: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Connection control

    func setKeepConnected(_ keep: Bool, for id: UUID) {
        guard var battery = store.battery(id) else { return }
        battery.keepConnected = keep
        store.update(battery)
        if keep {
            connectIfNeeded(id)
        } else {
            disconnect(id)
        }
    }

    func forget(_ id: UUID) {
        disconnect(id)
        store.delete(id)
    }

    private func connectIfNeeded(_ id: UUID) {
        guard state == .poweredOn,
              store.battery(id)?.keepConnected == true,
              let peripheral = peripheral(for: id)
        else { return }
        switch store.connections[id] ?? .disconnected {
        case .connecting, .connected:
            return
        case .disconnected, .failed:
            store.connections[id] = .connecting(since: Date())
            manager.connect(peripheral)
        }
    }

    private func disconnect(_ id: UUID) {
        writeCharacteristics[id] = nil
        missedResponses[id] = nil
        store.connections[id] = nil
        if let peripheral = peripherals[id], probeStarted[id] == nil {
            manager.cancelPeripheralConnection(peripheral)
        }
    }

    private func peripheral(for id: UUID) -> CBPeripheral? {
        let found = peripherals[id] ?? manager.retrievePeripherals(withIdentifiers: [id]).first
        found?.delegate = self
        peripherals[id] = found
        return found
    }

    // MARK: Diagnostics

    /// Connects, discovers every service and characteristic, and reads each readable value.
    /// Nothing is written to the battery.
    func probe(_ id: UUID) {
        guard state == .poweredOn, probeStarted[id] == nil, let peripheral = peripheral(for: id) else { return }
        probeStarted[id] = Date()
        pendingProbeWork[id] = 0
        var lines = ["iOS peripheral id: \(id.uuidString)"]
        if let ad = advertisements[id] { lines.append("advertisement: \(ad)") }
        probeReports[id] = ProbeReport(lines: lines, finished: false)
        if peripheral.state == .connected {
            peripheral.discoverServices(nil)
        } else {
            manager.connect(peripheral)
        }
    }

    private func log(_ line: String, for id: UUID) {
        probeReports[id]?.lines.append(line)
    }

    private func finishProbe(_ id: UUID, note: String? = nil) {
        guard probeStarted[id] != nil else { return }
        if let note { log(note, for: id) }
        probeStarted[id] = nil
        pendingProbeWork[id] = nil
        probeReports[id]?.finished = true
        if store.connections[id] == nil, let peripheral = peripherals[id] {
            manager.cancelPeripheralConnection(peripheral)
        }
    }

    private func adjustProbeWork(_ id: UUID, by delta: Int) {
        guard probeStarted[id] != nil else { return }
        let remaining = (pendingProbeWork[id] ?? 0) + delta
        pendingProbeWork[id] = remaining
        if remaining <= 0 { finishProbe(id) }
    }

    nonisolated private static func describe(_ value: Any) -> String {
        switch value {
        case let data as Data:
            return hex(data)
        case let uuids as [CBUUID]:
            return "[" + uuids.map(\.uuidString).joined(separator: ", ") + "]"
        case let dict as [CBUUID: Data]:
            return "{" + dict.map { "\($0.key.uuidString): \(hex($0.value))" }.sorted().joined(separator: ", ") + "}"
        default:
            return "\(value)"
        }
    }

    nonisolated private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    nonisolated private static func printable(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F })
        else { return nil }
        return text
    }

    // MARK: Timer

    private func tick() {
        let now = Date()
        store.tick(now)
        for (id, started) in probeStarted where now.timeIntervalSince(started) > probeTimeout {
            finishProbe(id, note: "timeout after \(Int(probeTimeout)) s")
        }
        for (id, status) in store.connections {
            switch status {
            case .connecting(let since) where now.timeIntervalSince(since) > connectTimeout:
                if let peripheral = peripherals[id] { manager.cancelPeripheralConnection(peripheral) }
                store.connections[id] = .failed
            case .connected:
                poll(id)
            default:
                break
            }
        }
    }

    private func poll(_ id: UUID) {
        guard let peripheral = peripherals[id], let characteristic = writeCharacteristics[id] else { return }
        let missed = (missedResponses[id] ?? 0) + 1
        missedResponses[id] = missed
        if missed > maxMissedResponses {
            manager.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.writeValue(BatteryProtocol.pollCommand, for: characteristic, type: .withResponse)
        peripheral.readRSSI()
    }

    private func startScan() {
        manager.scanForPeripherals(
            withServices: [CBUUID(string: BatteryProtocol.scanServiceUUID)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BatteryCentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            state = central.state
            if central.state == .poweredOn {
                startScan()
            } else {
                store.connections = [:]
                writeCharacteristics = [:]
                for id in probeStarted.keys { finishProbe(id, note: "Bluetooth state changed") }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let summary = advertisementData
            .map { "\($0.key)=\(Self.describe($0.value))" }
            .sorted()
            .joined(separator: "; ")
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            guard (localName ?? peripheral.name) == BatteryProtocol.advertisedName,
                  let manufacturerData,
                  let reading = BatteryReading(manufacturerData: manufacturerData)
            else { return }
            let id = peripheral.identifier
            if peripherals[id] == nil {
                peripheral.delegate = self
                peripherals[id] = peripheral
            }
            if advertisements[id] != summary { advertisements[id] = summary }
            // RSSI 127 means "not available" on iOS.
            store.record(reading, rssi: rssi == 127 ? nil : rssi, from: id)
            connectIfNeeded(id)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            let id = peripheral.identifier
            // A probe discovers every service; the poll path only needs the UART service.
            peripheral.discoverServices(probeStarted[id] != nil ? nil : [uartService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            if store.connections[id] != nil { store.connections[id] = .failed }
            finishProbe(id, note: "connect failed: \(error?.localizedDescription ?? "unknown")")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            writeCharacteristics[id] = nil
            missedResponses[id] = nil
            if store.connections[id] != nil {
                // Reconnect on the next advertisement while the user keeps the connection on.
                store.connections[id] = error == nil ? .disconnected : .failed
            }
            finishProbe(id, note: "disconnected: \(error?.localizedDescription ?? "by app")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BatteryCentral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            let services = peripheral.services ?? []
            if probeStarted[id] != nil {
                log("services: " + services.map(\.uuid.uuidString).joined(separator: ", "), for: id)
                if let error { log("service discovery error: \(error.localizedDescription)", for: id) }
                adjustProbeWork(id, by: services.count)
                if services.isEmpty { finishProbe(id) }
                for service in services { peripheral.discoverCharacteristics(nil, for: service) }
            }
            guard store.connections[id] != nil else { return }
            guard let uart = services.first(where: { $0.uuid == uartService }) else {
                store.connections[id] = .failed
                manager.cancelPeripheralConnection(peripheral)
                return
            }
            if probeStarted[id] == nil {
                peripheral.discoverCharacteristics([uartWrite, uartNotify], for: uart)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            let characteristics = service.characteristics ?? []

            if probeStarted[id] != nil {
                for characteristic in characteristics {
                    log("characteristic \(service.uuid.uuidString)/\(characteristic.uuid.uuidString) properties=0x\(String(characteristic.properties.rawValue, radix: 16))", for: id)
                    if characteristic.properties.contains(.read) {
                        adjustProbeWork(id, by: 1)
                        peripheral.readValue(for: characteristic)
                    }
                }
                if let error { log("characteristic discovery error: \(error.localizedDescription)", for: id) }
                adjustProbeWork(id, by: -1)
            }

            guard service.uuid == uartService, store.connections[id] != nil else { return }
            guard let write = characteristics.first(where: { $0.uuid == uartWrite }),
                  let notify = characteristics.first(where: { $0.uuid == uartNotify })
            else {
                store.connections[id] = .failed
                manager.cancelPeripheralConnection(peripheral)
                return
            }
            writeCharacteristics[id] = write
            missedResponses[id] = 0
            peripheral.setNotifyValue(true, for: notify)
            store.connections[id] = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            guard error == nil, rssi != 127 else { return }
            store.updateRSSI(rssi, for: peripheral.identifier)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let value = characteristic.value
        let uuid = characteristic.uuid
        let isNotifying = characteristic.isNotifying
        MainActor.assumeIsolated {
            let id = peripheral.identifier
            if uuid == uartNotify, isNotifying {
                guard let value, let reading = BatteryReading(response: value) else { return }
                missedResponses[id] = 0
                store.record(reading, rssi: nil, from: id)
                return
            }
            guard probeStarted[id] != nil else { return }
            if let error {
                log("read \(uuid.uuidString): error \(error.localizedDescription)", for: id)
            } else if let value {
                let text = Self.printable(value).map { " \"\($0)\"" } ?? ""
                log("read \(uuid.uuidString): \(Self.hex(value))\(text)", for: id)
            }
            adjustProbeWork(id, by: -1)
        }
    }
}
