import CoreMotion
import Foundation
import OctopiCore

/// Streams device motion (true-north frame, 100 Hz) as `MotionSample`s on the main actor.
/// `elapsed` is the CoreMotion timestamp, i.e. seconds since boot, the same base as `ProcessInfo.systemUptime`.
final class MotionService {
    private let manager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "octopi.motion"
        return q
    }()
    private(set) var isRunning = false
    var onSample: ((MotionSample) -> Void)?
    var onPressure: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    var authorizationDescription: String {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: "Allowed"
        case .denied: "Denied. Turn it on in Settings."
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        isRunning = true
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.deviceMotionUpdateInterval = 0.01
        manager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] data, _ in
            guard let data else { return }
            let sample = MotionSample(data)
            Task { @MainActor in self?.onSample?(sample) }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
                guard let data else { return }
                let kPa = data.pressure.doubleValue
                Task { @MainActor in self?.onPressure?(kPa) }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        isRunning = false
    }
}

extension MotionSample {
    nonisolated init(_ data: CMDeviceMotion) {
        let q = data.attitude.quaternion
        let g = 9.80665
        self.init(
            elapsed: data.timestamp,
            attitude: Quaternion(x: q.x, y: q.y, z: q.z, w: q.w),
            userAcceleration: Vector3(x: data.userAcceleration.x * g, y: data.userAcceleration.y * g, z: data.userAcceleration.z * g),
            rotationRate: Vector3(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z),
            gravity: Vector3(x: data.gravity.x, y: data.gravity.y, z: data.gravity.z),
            magneticField: Vector3(x: data.magneticField.field.x, y: data.magneticField.field.y, z: data.magneticField.field.z),
            magneticAccuracy: Double(data.magneticField.accuracy.rawValue)
        )
    }
}
