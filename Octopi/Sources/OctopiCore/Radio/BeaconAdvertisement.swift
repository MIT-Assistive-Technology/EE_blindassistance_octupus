import Foundation

/// The BLE advertisement payload the Octopi beacon broadcasts in its manufacturer-specific data.
///
/// Layout (little-endian, 14 bytes), see docs/HARDWARE_INTERFACE.md:
/// ```
/// 0-1  company id          0xFFFF until we have an assigned Bluetooth SIG id
/// 2    magic               0x4F ('O')
/// 3    format version      0x01
/// 4-7  serial              uint32
/// 8    flags               bit0 moving now, bit1 battery low, bit2 button pressed, bit3 charging
/// 9    battery percent     0...100, 0xFF unknown
/// 10-11 seconds since last motion  uint16, 0xFFFF unknown
/// 12   tx power at 1 m     int8 dBm (calibrated RSSI)
/// 13   sequence            uint8, increments every advertisement
/// ```
nonisolated public struct BeaconAdvertisement: Equatable, Sendable {
    public static let companyID: UInt16 = 0xFFFF
    public static let magic: UInt8 = 0x4F
    public static let version: UInt8 = 0x01
    public static let length = 14

    public var serial: UInt32
    public var isMoving: Bool
    public var isBatteryLow: Bool
    public var isButtonPressed: Bool
    public var isCharging: Bool
    public var batteryPercent: Int?
    public var secondsSinceMotion: Double?
    public var txPowerAt1m: Double
    public var sequence: UInt8

    public var identifier: BeaconIdentifier { BeaconIdentifier(String(format: "OCT-%08X", serial)) }

    public init(serial: UInt32, isMoving: Bool, isBatteryLow: Bool = false, isButtonPressed: Bool = false, isCharging: Bool = false, batteryPercent: Int? = nil, secondsSinceMotion: Double? = nil, txPowerAt1m: Double = -59, sequence: UInt8 = 0) {
        self.serial = serial
        self.isMoving = isMoving
        self.isBatteryLow = isBatteryLow
        self.isButtonPressed = isButtonPressed
        self.isCharging = isCharging
        self.batteryPercent = batteryPercent
        self.secondsSinceMotion = secondsSinceMotion
        self.txPowerAt1m = txPowerAt1m
        self.sequence = sequence
    }

    /// Parse manufacturer data. Returns nil for anything that is not an Octopi beacon.
    public init?(manufacturerData data: Data) {
        guard data.count >= Self.length else { return nil }
        let bytes = [UInt8](data)
        let company = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        guard company == Self.companyID, bytes[2] == Self.magic, bytes[3] == Self.version else { return nil }
        serial = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
        let flags = bytes[8]
        isMoving = flags & 0x01 != 0
        isBatteryLow = flags & 0x02 != 0
        isButtonPressed = flags & 0x04 != 0
        isCharging = flags & 0x08 != 0
        batteryPercent = bytes[9] == 0xFF ? nil : Int(min(bytes[9], 100))
        let age = UInt16(bytes[10]) | UInt16(bytes[11]) << 8
        secondsSinceMotion = age == 0xFFFF ? nil : Double(age)
        txPowerAt1m = Double(Int8(bitPattern: bytes[12]))
        sequence = bytes[13]
    }

    /// Encode (used by tests and by the beacon simulator in the app).
    public var manufacturerData: Data {
        var bytes = [UInt8](repeating: 0, count: Self.length)
        bytes[0] = UInt8(Self.companyID & 0xFF)
        bytes[1] = UInt8(Self.companyID >> 8)
        bytes[2] = Self.magic
        bytes[3] = Self.version
        bytes[4] = UInt8(serial & 0xFF)
        bytes[5] = UInt8((serial >> 8) & 0xFF)
        bytes[6] = UInt8((serial >> 16) & 0xFF)
        bytes[7] = UInt8((serial >> 24) & 0xFF)
        var flags: UInt8 = 0
        if isMoving { flags |= 0x01 }
        if isBatteryLow { flags |= 0x02 }
        if isButtonPressed { flags |= 0x04 }
        if isCharging { flags |= 0x08 }
        bytes[8] = flags
        bytes[9] = batteryPercent.map { UInt8(min(max($0, 0), 100)) } ?? 0xFF
        let age = secondsSinceMotion.map { UInt16(min(max($0, 0), 65534)) } ?? 0xFFFF
        bytes[10] = UInt8(age & 0xFF)
        bytes[11] = UInt8(age >> 8)
        bytes[12] = UInt8(bitPattern: Int8(min(max(txPowerAt1m, -127), 127)))
        bytes[13] = sequence
        return Data(bytes)
    }
}
