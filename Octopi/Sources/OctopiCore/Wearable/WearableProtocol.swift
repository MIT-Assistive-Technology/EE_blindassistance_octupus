import Foundation

/// The BLE contract between the phone and the haptic band. Mirrored in docs/HARDWARE_INTERFACE.md.
nonisolated public enum WearableProtocol {
    public static let serviceUUID = "6F637470-6900-4F63-746F-706900000001"
    /// Phone → band. Write without response.
    public static let commandCharacteristicUUID = "6F637470-6900-4F63-746F-706900000002"
    /// Band → phone. Notify.
    public static let eventCharacteristicUUID = "6F637470-6900-4F63-746F-706900000003"
    /// Band → phone. Read + notify: [battery %, charging, mode, firmware major, firmware minor].
    public static let statusCharacteristicUUID = "6F637470-6900-4F63-746F-706900000004"
    /// Advertised local name prefix, e.g. "Octopi Band 1A2B".
    public static let namePrefix = "Octopi Band"

    public enum Mode: UInt8, Codable, Sendable {
        case idle = 0
        /// Phone drives every buzz.
        case path = 1
        /// Band locks onto a beacon by itself and pulses by RSSI (no phone needed).
        case simple = 2
    }

    public enum Button: UInt8, Codable, Sendable {
        case record = 1
        case power = 2
    }

    public enum ButtonAction: UInt8, Codable, Sendable {
        case single = 1
        case double = 2
        case long = 3
    }

    /// Phone → band messages.
    public enum Command: Equatable, Sendable {
        /// Play a pattern. `parameterMs` is pattern-specific (proximity pulse interval). `intensity` is 0...100.
        case play(pattern: HapticPattern, intensity: UInt8, repeatCount: UInt8, parameterMs: UInt16)
        case stop
        case setMode(Mode)
        /// Which beacon the band should lock onto in Simple mode.
        case setSimpleTarget(serial: UInt32)
        case ping

        public var opcode: UInt8 {
            switch self {
            case .play: 0x01
            case .stop: 0x02
            case .setMode: 0x03
            case .setSimpleTarget: 0x04
            case .ping: 0x05
            }
        }

        public var encoded: Data {
            var bytes: [UInt8] = [opcode]
            switch self {
            case .play(let pattern, let intensity, let repeatCount, let parameterMs):
                bytes += [pattern.wireID, min(intensity, 100), repeatCount, UInt8(parameterMs & 0xFF), UInt8(parameterMs >> 8)]
            case .stop, .ping:
                break
            case .setMode(let mode):
                bytes.append(mode.rawValue)
            case .setSimpleTarget(let serial):
                bytes += [UInt8(serial & 0xFF), UInt8((serial >> 8) & 0xFF), UInt8((serial >> 16) & 0xFF), UInt8((serial >> 24) & 0xFF)]
            }
            return Data(bytes)
        }
    }

    /// Band → phone messages.
    public enum Event: Equatable, Sendable {
        case button(Button, ButtonAction)
        case battery(percent: Int, charging: Bool)
        case ack(opcode: UInt8, ok: Bool)
        case modeChanged(Mode)
        /// Simple mode: which beacon the band is locked onto and how strong it is.
        case simpleLock(serial: UInt32, rssi: Int)

        public init?(data: Data) {
            let bytes = [UInt8](data)
            guard let type = bytes.first else { return nil }
            switch type {
            case 0x10:
                guard bytes.count >= 3, let button = Button(rawValue: bytes[1]), let action = ButtonAction(rawValue: bytes[2]) else { return nil }
                self = .button(button, action)
            case 0x11:
                guard bytes.count >= 3 else { return nil }
                self = .battery(percent: Int(min(bytes[1], 100)), charging: bytes[2] != 0)
            case 0x12:
                guard bytes.count >= 3 else { return nil }
                self = .ack(opcode: bytes[1], ok: bytes[2] == 0)
            case 0x13:
                guard bytes.count >= 2, let mode = Mode(rawValue: bytes[1]) else { return nil }
                self = .modeChanged(mode)
            case 0x14:
                guard bytes.count >= 6 else { return nil }
                let serial = UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24
                self = .simpleLock(serial: serial, rssi: Int(Int8(bitPattern: bytes[5])))
            default:
                return nil
            }
        }

        /// Encode (used by tests and the band simulator).
        public var encoded: Data {
            switch self {
            case .button(let button, let action): Data([0x10, button.rawValue, action.rawValue])
            case .battery(let percent, let charging): Data([0x11, UInt8(min(max(percent, 0), 100)), charging ? 1 : 0])
            case .ack(let opcode, let ok): Data([0x12, opcode, ok ? 0 : 1])
            case .modeChanged(let mode): Data([0x13, mode.rawValue])
            case .simpleLock(let serial, let rssi):
                Data([0x14, UInt8(serial & 0xFF), UInt8((serial >> 8) & 0xFF), UInt8((serial >> 16) & 0xFF), UInt8((serial >> 24) & 0xFF), UInt8(bitPattern: Int8(min(max(rssi, -127), 127)))])
            }
        }
    }

    public struct Status: Equatable, Sendable {
        public var batteryPercent: Int
        public var charging: Bool
        public var mode: Mode
        public var firmware: String

        public init?(data: Data) {
            let bytes = [UInt8](data)
            guard bytes.count >= 5, let mode = Mode(rawValue: bytes[2]) else { return nil }
            batteryPercent = Int(min(bytes[0], 100))
            charging = bytes[1] != 0
            self.mode = mode
            firmware = "\(bytes[3]).\(bytes[4])"
        }
    }
}
