import CoreLocation
import CoreMotion
import Foundation
import Observation

@Observable
final class LogPath: NSObject, CLLocationManagerDelegate {
    var samples: [Sample] = []
    var isLogging = false
    var status = "Ready"
    var fileURL: URL?
    var facingDegrees: Double?
    private var watchingFacing = false
    private let manager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let location = CLLocationManager()
    private let queue = OperationQueue()
    private var writer: LogFile?
    private var latestSteps = 0.0
    private var latestDistance = 0.0

    override init() {
        super.init()
        queue.maxConcurrentOperationCount = 1
        location.delegate = self
    }

    func toggle() { isLogging ? stop() : start() }

    func start() {
        guard !isLogging else { return }
        location.requestWhenInUseAuthorization()
        samples.removeAll()
        latestSteps = 0
        latestDistance = 0
        writer = LogFile.create()
        fileURL = writer?.url
        guard let writer else { status = "Could not open file"; return }
        guard manager.isDeviceMotionAvailable else { status = "Log is unavailable :("; writer.close(); return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        status = frame == .xTrueNorthZVertical ? "Logging" : "Logging without north"
        let origin = Date()
        isLogging = true
        beginMotion { [weak self] data in
            let packet = PathPacket(data, elapsed: Date().timeIntervalSince(origin))
            Task { @MainActor in
                self?.append(packet)
            }
        }
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: origin) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.doubleValue
            let distance = data.distance?.doubleValue ?? 0
            Task { @MainActor in
                self?.latestSteps = steps
                self?.latestDistance = distance
            }
        }
    }

    func watchFacing() {
        watchingFacing = true
        location.requestWhenInUseAuthorization()
        if isLogging {
            publishFacing(samples.last?.heading)
            return
        }
        beginMotion { [weak self] data in
            let packet = PathPacket(data, elapsed: 0)
            Task { @MainActor in
                guard let self, self.watchingFacing else { return }
                self.publishFacing(packet.sample().heading)
            }
        }
    }

    func stopFacing() {
        watchingFacing = false
        facingDegrees = nil
        if !isLogging { manager.stopDeviceMotionUpdates() }
    }

    func stop() {
        watchingFacing = false
        manager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        writer?.close()
        writer = nil
        isLogging = false
        status = samples.isEmpty ? "Ready" : "Saved"
    }

    func importLog(from url: URL) {
        guard !isLogging else { return }
        guard let stored = Self.store(url) else { status = "Could not copy file"; return }
        let loaded = LogFile.load(stored)
        guard !loaded.isEmpty else { status = "Not a log..."; return }
        samples = loaded
        fileURL = stored
        status = stored.deletingPathExtension().lastPathComponent
    }

    private static func store(_ url: URL) -> URL? {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let source = url.standardizedFileURL
        let root = folder.standardizedFileURL.path
        if source.path == root || source.path.hasPrefix(root + "/") { return source }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "csv" : source.pathExtension
        var dest = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            for ext in ["planned", "course"] {
                let side = source.deletingPathExtension().appendingPathExtension(ext)
                let sideDest = dest.deletingPathExtension().appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: side.path), !FileManager.default.fileExists(atPath: sideDest.path) {
                    _ = try? FileManager.default.copyItem(at: side, to: sideDest)
                }
            }
            return dest
        } catch {
            return nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    private func append(_ packet: PathPacket) {
        guard isLogging else { return }
        var row = packet.sample()
        row.pedometerSteps = latestSteps
        row.pedometerDistance = latestDistance
        samples.append(row)
        writer?.append(row)
        if watchingFacing { publishFacing(row.heading) }
    }

    private func beginMotion(_ handle: @escaping (CMDeviceMotion) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.deviceMotionUpdateInterval = isLogging ? Stats.Log.pathInterval : 0.1
        manager.startDeviceMotionUpdates(using: frame, to: queue) { data, _ in
            guard let data else { return }
            handle(data)
        }
    }

    private func publishFacing(_ radians: Double?) {
        guard let radians else { return }
        facingDegrees = radians * 180 / .pi
    }

}

nonisolated struct PathPacket: Sendable {
    var elapsed: Double
    var qx, qy, qz, qw: Double
    var ax, ay, az: Double
    var rx, ry, rz: Double
    var gx, gy, gz: Double
    var mx, my, mz: Double
    var accuracy: Double

    init(_ data: CMDeviceMotion, elapsed: Double) {
        let q = data.attitude.quaternion
        let field = data.magneticField.field
        self.elapsed = elapsed
        qx = q.x; qy = q.y; qz = q.z; qw = q.w
        ax = data.userAcceleration.x; ay = data.userAcceleration.y; az = data.userAcceleration.z
        rx = data.rotationRate.x; ry = data.rotationRate.y; rz = data.rotationRate.z
        gx = data.gravity.x; gy = data.gravity.y; gz = data.gravity.z
        mx = field.x; my = field.y; mz = field.z
        accuracy = Double(data.magneticField.accuracy.rawValue)
    }

    @MainActor func sample() -> Sample {
        let quat = Quat(x: qx, y: qy, z: qz, w: qw)
        let user = Vec3(x: ax, y: ay, z: az).scaled(Stats.Path.gravity)
        let rotation = Vec3(x: rx, y: ry, z: rz)
        let gravity = Vec3(x: gx, y: gy, z: gz)
        let magnetic = Vec3(x: mx, y: my, z: mz)
        let world = Sample.world(user: user, rotation: rotation, quaternion: quat)
        return Sample(
            elapsed: elapsed, isPath: true, quaternion: quat,
            deviceUserAcceleration: user, deviceRotation: rotation, deviceGravity: gravity,
            magneticField: magnetic, magneticAccuracy: accuracy,
            eastAcceleration: world.east, northAcceleration: world.north, upAcceleration: world.up,
            yawRate: world.yawRate, heading: world.heading, pedometerSteps: 0, pedometerDistance: 0
        )
    }
}
