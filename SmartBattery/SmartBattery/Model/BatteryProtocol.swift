import Foundation

/// Battery form factor. The raw value matches the type bit in the advertisement (0 = AA, 1 = AAA).
enum BatterySize: Int, Codable, CaseIterable, Sendable {
    case aa = 0
    case aaa = 1

    var label: String {
        switch self {
        case .aa: "AA"
        case .aaa: "AAA"
        }
    }
}

/// One battery reading decoded from Smart15V manufacturer data or from a connection response.
///
/// Manufacturer data layout:
/// - bytes 0...1: company identifier (not used)
/// - byte 2: voltage bits 9...2
/// - byte 3: bits 7...6 voltage bits 1...0, bit 1 size (0 = AA, 1 = AAA), bit 0 charging
/// - bytes 4...5: charge count, big endian; 0xFFFF means "no count"
struct BatteryReading: Codable, Equatable, Sendable {
    /// 10-bit voltage value, the input of ``CapacityTable``.
    let rawVoltage: Int
    let isCharging: Bool
    let reportedSize: BatterySize
    let chargeCount: Int?

    init(rawVoltage: Int, isCharging: Bool, reportedSize: BatterySize, chargeCount: Int?) {
        self.rawVoltage = rawVoltage
        self.isCharging = isCharging
        self.reportedSize = reportedSize
        self.chargeCount = chargeCount
    }

    /// Decodes the advertisement payload. Returns nil when the payload is shorter than 6 bytes.
    init?(manufacturerData data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        self.init(fields: Array(bytes[2...5]))
    }

    /// Decodes the notification that answers ``BatteryProtocol/pollCommand``:
    /// `E2 44 <company 2 bytes> <voltage/flags 2 bytes> <count 2 bytes>`.
    init?(response data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, bytes[0] == 0xE2, bytes[1] == 0x44 else { return nil }
        self.init(fields: Array(bytes[4...7]))
    }

    private init(fields f: [UInt8]) {
        rawVoltage = Int(f[0]) << 2 | Int(f[1]) >> 6
        isCharging = f[1] & 0x01 != 0
        reportedSize = (f[1] & 0x02) == 0 ? .aa : .aaa
        let count = Int(f[2]) << 8 | Int(f[3])
        chargeCount = count == 0xFFFF ? nil : count
    }
}

enum BatteryProtocol {
    static let advertisedName = "Smart15V"
    static let scanServiceUUID = "AF30"
    static let uartServiceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Written with response by the app.
    static let uartWriteUUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Notifies the response.
    static let uartNotifyUUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
    /// Sent once per second while connected.
    static let pollCommand = Data([0xE1, 0x05, 0x00, 0x02])

    /// A battery without an advertisement for this long is shown as waiting.
    static let offlineInterval: TimeInterval = 35
    /// Maximum number of registered batteries.
    static let registrationLimit = 999
}

/// Voltage-to-capacity conversion for each battery size.
enum CapacityTable {
    static let aaa: [Int] = [
        100, 99, 98, 97, 96, 95, 94, 93, 92, 91, 90, 89, 88, 87, 86, 85, 82, 81, 79, 78,
        76, 75, 73, 71, 70, 68, 66, 64, 62, 61, 59, 57, 55, 53, 51, 48, 46, 43, 40, 37,
        34, 31, 27, 24, 21, 20, 16, 14, 12, 10, 8, 7, 6, 5,
    ]

    static let aa: [Int] = [
        100, 99, 98, 98, 97, 97, 96, 96, 95, 94, 93, 92, 91, 89, 89, 88, 87, 86, 85, 85,
        85, 84, 83, 82, 81, 80, 79, 78, 77, 76, 75, 74, 73, 72, 71, 69, 68, 67, 65, 65,
        64, 63, 61, 59, 58, 56, 54, 51, 47, 46, 45, 40, 37, 33, 28, 26, 25, 23, 21, 20,
        18, 17, 16, 15, 14, 13, 12, 11, 9, 8, 7, 6, 5, 5,
    ]

    static func percent(rawVoltage v: Int, size: BatterySize) -> Int {
        switch size {
        case .aaa:
            if v >= 407 { return 100 }
            if v <= 354 { return 5 }
            return aaa[407 - v]
        case .aa:
            if v >= 408 { return 100 }
            if v <= 335 { return 5 }
            return aa[408 - v]
        }
    }
}
