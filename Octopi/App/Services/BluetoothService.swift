import CoreBluetooth
import Foundation
import OctopiCore

/// The beacon advertises this service so iOS can scan for it in the background.
enum BeaconBLE {
    static let serviceUUID = CBUUID(string: "6F637470-6900-4F63-746F-706900000010")
}

/// Central role: scans for beacons, connects to the band, and exposes the band as a `HapticOutput`.
final class BluetoothService: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct NearbyBeacon: Identifiable, Equatable {
        var id: BeaconIdentifier { advertisement.identifier }
        var advertisement: BeaconAdvertisement
        var rssi: Double
        var lastSeen: Date
    }

    enum BandState: Equatable {
        case unavailable, off, scanning, connecting, connected, disconnected
        var spoken: String {
        switch self {
        case .unavailable: "Bluetooth not available"
        case .off: "Bluetooth is off"
        case .scanning: "Looking for your band"
        case .connecting: "Connecting to band"
        case .connected: "Band connected"
        case .disconnected: "Band not connected"
        }
        }
    }

    private var central: CBCentralManager!
    private var band: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var wantsBand = false
    private(set) var bandState = BandState.disconnected
    private(set) var nearbyBeacons: [BeaconIdentifier: NearbyBeacon] = [:]
    private(set) var isScanning = false
    var preferredBandIdentifier: String?

    var onBeacon: ((BeaconAdvertisement, Double) -> Void)?
    var onBandEvent: ((WearableProtocol.Event) -> Void)?
    var onBandStatus: ((WearableProtocol.Status) -> Void)?
    var onBandConnection: ((Bool) -> Void)?
    var onBandDiscovered: ((String) -> Void)?
    var onStateChange: (() -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    var isPoweredOn: Bool { central.state == .poweredOn }

    var stateDescription: String {
        switch central.state {
        case .poweredOn: "On"
        case .poweredOff: "Off"
        case .unauthorized: "Denied. Turn it on in Settings."
        case .unsupported: "Not supported on this device"
        default: "Not ready"
        }
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: [BeaconBLE.serviceUUID, CBUUID(string: WearableProtocol.serviceUUID)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        if wantsBand, band == nil { bandState = .scanning }
        onStateChange?()
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
    }

    /// Connect to the first band found (or the remembered one).
    func connectBand() {
        wantsBand = true
        if let band, band.state != .connected {
        bandState = .connecting
        central.connect(band)
        } else if band == nil {
        if let id = preferredBandIdentifier, let uuid = UUID(uuidString: id),
               let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            band = known
            known.delegate = self
            bandState = .connecting
            central.connect(known)
        } else {
            startScanning()
        }
        }
        onStateChange?()
    }

    func forgetBand() {
        wantsBand = false
        if let band { central.cancelPeripheralConnection(band) }
        band = nil
        preferredBandIdentifier = nil
        bandState = .disconnected
        onStateChange?()
    }

    func send(_ command: WearableProtocol.Command) {
        guard let band, let characteristic = commandCharacteristic, band.state == .connected else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        band.writeValue(command.encoded, for: characteristic, type: type)
    }

    func pruneStaleBeacons(olderThan seconds: TimeInterval = 15) {
        let cutoff = Date().addingTimeInterval(-seconds)
        nearbyBeacons = nearbyBeacons.filter { $0.value.lastSeen >= cutoff }
    }

    // MARK: CBCentralManagerDelegate (delivered on the main queue)

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if bandState == .off || bandState == .unavailable { bandState = .disconnected }
            startScanning()
            if wantsBand { connectBand() }
        case .poweredOff: bandState = .off
        case .unsupported, .unauthorized: bandState = .unavailable
        default: break
        }
        onStateChange?()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, let advertisement = BeaconAdvertisement(manufacturerData: data) {
            let rssi = RSSI.doubleValue
            guard rssi < 0, rssi > -120 else { return }
            nearbyBeacons[advertisement.identifier] = NearbyBeacon(advertisement: advertisement, rssi: rssi, lastSeen: Date())
            onBeacon?(advertisement, rssi)
            return
        }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.hasPrefix(WearableProtocol.namePrefix) || services.contains(CBUUID(string: WearableProtocol.serviceUUID)) else { return }
        onBandDiscovered?(name)
        guard wantsBand, band == nil else { return }
        if let preferred = preferredBandIdentifier, preferred != peripheral.identifier.uuidString { return }
        band = peripheral
        peripheral.delegate = self
        bandState = .connecting
        central.connect(peripheral)
        onStateChange?()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        preferredBandIdentifier = peripheral.identifier.uuidString
        peripheral.discoverServices([CBUUID(string: WearableProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        bandState = .disconnected
        onStateChange?()
        if wantsBand { central.connect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        commandCharacteristic = nil
        statusCharacteristic = nil
        bandState = .disconnected
        onBandConnection?(false)
        onStateChange?()
        if wantsBand { central.connect(peripheral) }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == CBUUID(string: WearableProtocol.serviceUUID) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid.uuidString.uppercased() {
            case WearableProtocol.commandCharacteristicUUID: commandCharacteristic = characteristic
            case WearableProtocol.eventCharacteristicUUID: peripheral.setNotifyValue(true, for: characteristic)
            case WearableProtocol.statusCharacteristicUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            default: break
            }
        }
        if commandCharacteristic != nil {
            bandState = .connected
            onBandConnection?(true)
            onStateChange?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()
        if uuid == WearableProtocol.eventCharacteristicUUID, let event = WearableProtocol.Event(data: data) {
            onBandEvent?(event)
        } else if uuid == WearableProtocol.statusCharacteristicUUID, let status = WearableProtocol.Status(data: data) {
            onBandStatus?(status)
        }
    }
}

/// The band as a haptic output: patterns become BLE commands.
final class BandLink: HapticOutput {
    private let bluetooth: BluetoothService
    init(bluetooth: BluetoothService) { self.bluetooth = bluetooth }

    var isAvailable: Bool { bluetooth.bandState == .connected }

    func play(_ pattern: HapticPattern, parameterMs: Int?) {
        let repeats: UInt8 = pattern == .proximityPulse || pattern == .leftBehindAlert ? 0 : 1 // 0 = until stopped
        bluetooth.send(.play(pattern: pattern, intensity: 100, repeatCount: repeats, parameterMs: UInt16(clamping: parameterMs ?? 0)))
    }

    func stop() { bluetooth.send(.stop) }
}
