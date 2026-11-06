import Foundation
import Observation
import OctopiCore
import UIKit

/// Wires the sensors and outputs to the core session and exposes observable state to the views.
@Observable
final class AppModel {
    let session: OctopiSession
    let settingsStore = SettingsStore()
    let motion = MotionService()
    let location = LocationService()
    let bluetooth = BluetoothService()
    let phoneHaptics = PhoneHaptics()
    let announcer = Announcer()
    let router: HapticRouter
    let simulator = HardwareSimulator()

    /// Bumped whenever session state may have changed; views read it to refresh.
    private(set) var revision = 0
    var setupComplete: Bool { didSet { settingsStore.setupComplete = setupComplete } }
    var settings: OctopiSettings {
        didSet {
            session.settings = settings
            settingsStore.save(settings)
            announcer.speakWhenVoiceOverOff = settings.speakGuidance
            router.mirrorToPhone = settings.mirrorHapticsToPhone
        }
    }
    var isSimulating: Bool { didSet { applySimulation() } }
    private(set) var started = false
    #if DEBUG
    private var demo: DemoDriver?
    #endif
    private var ticker: Timer?
    private var fastTicker: Timer?
    private var lastSavedBeacons: [PairedBeacon] = []

    init() {
        let store = settingsStore
        let loadedSettings = store.loadSettings()
        settings = loadedSettings
        setupComplete = store.setupComplete
        router = HapticRouter(band: nil, phone: nil)
        let placeStore = JSONPlaceStore.inDocuments()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") { UIView.setAnimationsEnabled(false) }
        if arguments.contains("-skipSetup") { store.setupComplete = true; setupComplete = true }

        if arguments.contains("-resetState") {
            // Must happen before the session loads the store.
            store.setupComplete = false
            setupComplete = false
            try? placeStore.save([])
            store.save(beacons: [])
        }
        session = OctopiSession(store: placeStore, haptics: router, settings: loadedSettings, clock: { ProcessInfo.processInfo.systemUptime })
        #if targetEnvironment(simulator)
        isSimulating = !arguments.contains("-realHardware")
        #else
        isSimulating = arguments.contains("-simulateHardware")
        #endif
        router.phone = phoneHaptics
        router.band = BandLink(bluetooth: bluetooth)
        router.mirrorToPhone = settings.mirrorHapticsToPhone
        announcer.speakWhenVoiceOverOff = settings.speakGuidance
        session.restoreBeacons(store.loadBeacons())
        lastSavedBeacons = session.beacons
        wire()
    }

    // MARK: Derived state (reading `revision` makes views re-render when the session changes)

    var places: [Place] { _ = revision; return session.places }
    var beacons: [PairedBeacon] { _ = revision; return session.beacons }
    var navigation: NavigationStatus? { _ = revision; return session.navigation }
    var activeAlert: ActiveAlert? { _ = revision; return session.activeAlert }
    var diagnostics: SessionDiagnostics { _ = revision; return session.diagnostics }
    var announcements: [Announcement] { _ = revision; return announcer.log }
    var bandBattery: Int? { _ = revision; return session.bandBattery }
    var nearbyUnpairedBeacons: [BluetoothService.NearbyBeacon] {
        _ = revision
        let paired = Set(session.beacons.map(\.id))
        if isSimulating {
            return simulator.beacons.filter { !paired.contains(BeaconAdvertisement(serial: $0.id, isMoving: true).identifier) }
                .map { BluetoothService.NearbyBeacon(advertisement: BeaconAdvertisement(serial: $0.id, isMoving: true, batteryPercent: $0.battery), rssi: -60, lastSeen: Date()) }
        }
        return bluetooth.nearbyBeacons.values.filter { !paired.contains($0.id) }.sorted { $0.rssi > $1.rssi }
    }

    var bandStatusText: String {
        _ = revision
        if isSimulating { return "Simulated band connected" }
        var text = bluetooth.bandState.spoken
        if let battery = session.bandBattery, bluetooth.bandState == .connected { text += ", battery \(battery) percent" }
        return text
    }

    var anchorStatusText: String {
        let d = diagnostics
        guard let quality = d.anchorQuality else { return d.gpsDegraded ? "No GPS anchor yet, signal is weak" : "No GPS anchor yet" }
        var text = "GPS anchor \(quality.rawValue)"
        if let accuracy = d.anchorAccuracy { text += ", \(Int(accuracy)) metres" }
        if let age = d.anchorAgeSeconds { text += ", \(Self.age(age)) old" }
        return text
    }

    static func age(_ seconds: Double) -> String {
        if seconds < 90 { return "\(Int(seconds)) seconds" }
        if seconds < 5400 { return "\(Int(seconds / 60)) minutes" }
        if seconds < 172_800 { return "\(Int(seconds / 3600)) hours" }
        return "\(Int(seconds / 86400)) days"
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        if !isSimulating {
            motion.start()
            location.start()
            bluetooth.preferredBandIdentifier = settingsStore.bandIdentifier
            if settingsStore.bandIdentifier != nil { bluetooth.connectBand() }
        }
        applySimulation()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoWalk") {
            demo = DemoDriver(model: self)
            demo?.start()
        }
        #endif
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        fastTicker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session.navigation != nil else { return }
                self.revision += 1
            }
        }
    }

    private func tick() {
        session.tick()
        #if DEBUG
        demo?.tick(now: ProcessInfo.processInfo.systemUptime)
        #endif
        bluetooth.pruneStaleBeacons()
        if session.beacons != lastSavedBeacons {
            lastSavedBeacons = session.beacons
            settingsStore.save(beacons: lastSavedBeacons)
        }
        revision += 1
    }

    private func wire() {
        session.onAnnouncement = { [weak self] announcement in
            self?.announcer.announce(announcement)
            self?.revision += 1
        }
        session.onBandCommand = { [weak self] command in
            guard let self, !self.isSimulating else { return }
            self.bluetooth.send(command)
        }
        session.onPlacesChanged = { [weak self] in self?.revision += 1 }
        motion.onSample = { [weak self] sample in self?.session.handleMotion(sample) }
        motion.onPressure = { [weak self] kPa in self?.session.currentPressureKPa = kPa }
        location.onFix = { [weak self] fix in self?.session.handleLocation(fix) }
        location.onAuthorizationChange = { [weak self] in self?.revision += 1 }
        bluetooth.onBeacon = { [weak self] advertisement, rssi in self?.session.handleBeacon(advertisement, rssi: rssi) }
        bluetooth.onBandEvent = { [weak self] event in self?.session.handleWearable(event); self?.revision += 1 }
        bluetooth.onBandStatus = { [weak self] status in self?.session.handleWearable(.battery(percent: status.batteryPercent, charging: status.charging)) }
        bluetooth.onBandConnection = { [weak self] connected in
            guard let self else { return }
            if connected { settingsStore.bandIdentifier = bluetooth.preferredBandIdentifier }
            session.bandConnectionChanged(connected: connected)
            revision += 1
        }
        bluetooth.onStateChange = { [weak self] in self?.revision += 1 }
        simulator.onMotion = { [weak self] sample in self?.session.handleMotion(sample) }
        simulator.onBeacon = { [weak self] advertisement, rssi in self?.session.handleBeacon(advertisement, rssi: rssi) }
        simulator.onFix = { [weak self] fix in self?.session.handleLocation(fix) }
        simulator.onBandEvent = { [weak self] event in self?.session.handleWearable(event); self?.revision += 1 }
        simulator.positionProvider = { [weak self] in self?.session.reckoner.position ?? .origin }
    }

    private func applySimulation() {
        guard started else { return }
        if isSimulating {
            motion.stop()
            router.band = simulator.band
            simulator.start()
            session.bandConnectionChanged(connected: true)
        } else {
            simulator.stop()
            router.band = BandLink(bluetooth: bluetooth)
            session.bandConnectionChanged(connected: bluetooth.bandState == .connected)
            motion.start()
            location.start()
        }
        revision += 1
    }

    // MARK: Actions

    func dropPin(name: String? = nil) {
        session.dropPin(name: name, origin: .app)
        revision += 1
    }

    func navigate(to place: Place) {
        session.startNavigation(to: place.id)
        revision += 1
    }

    func stopNavigation() {
        session.stopNavigation()
        revision += 1
    }

    func snoozeAlert() { session.snoozeAlert(); revision += 1 }
    func dismissAlert() { session.dismissAlert(); revision += 1 }
    func findLeftBehindItem() { session.findLeftBehindItem(); revision += 1 }

    func rename(_ place: Place, to name: String) { session.rename(place.id, to: name); revision += 1 }

    /// Import a pack file picked by the user. Returns what to tell them.
    func importPack(from url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let pack = try PlacePack.decode(try Data(contentsOf: url))
            let result = session.importPack(pack)
            revision += 1
            return "Imported \(pack.name): \(result.spoken)"
        } catch let error as PlacePack.PackError {
            let text = error.errorDescription ?? "Could not read the pack."
            announcer.announce(Announcement(text, priority: .high))
            return text
        } catch {
            announcer.announce(Announcement("Could not read that file.", priority: .high))
            return "Could not read that file."
        }
    }

    /// Write all places to a pack file in the temporary folder for sharing. Nil when there is nothing to share.
    func exportPackURL() -> URL? {
        guard !session.places.isEmpty else { return nil }
        let pack = session.exportPack(name: "Octopi places \(Self.packStamp.string(from: Date()))", author: UIDevice.current.name)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("octopi-places.json")
        guard let data = try? pack.encoded(), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static let packStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
    func delete(_ place: Place) { session.delete(place.id); revision += 1 }

    func pair(_ beacon: BluetoothService.NearbyBeacon, name: String) {
        session.pairBeacon(beacon.advertisement, name: name)
        revision += 1
        #if DEBUG
        demo?.didPair(serial: beacon.advertisement.serial)
        #endif
    }

    func unpair(_ beacon: PairedBeacon) { session.unpairBeacon(beacon.id); revision += 1 }
    func setHandedOff(_ beacon: PairedBeacon, _ value: Bool) { session.setHandedOff(beacon.id, value); revision += 1 }
    func setSimpleModeBeacon(_ beacon: PairedBeacon?) {
        session.setSimpleModeBeacon(beacon?.id)
        settings = session.settings
    }

    func connectBand() {
        if isSimulating { return }
        bluetooth.connectBand()
        revision += 1
    }

    func forgetBand() {
        bluetooth.forgetBand()
        settingsStore.bandIdentifier = nil
        revision += 1
    }

    func requestMotionPermission() {
        motion.start()
        revision += 1
    }

    func requestLocationPermission() {
        location.requestPermission()
        revision += 1
    }

    func playTutorial(_ pattern: HapticPattern) {
        router.play(pattern, parameterMs: pattern == .proximityPulse ? 400 : nil)
        announcer.announce(Announcement("\(pattern.spokenName). \(pattern.feelDescription)", priority: .high))
        revision += 1
    }

    func stopHaptics() { router.stop() }

    func bump() { revision += 1 }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
