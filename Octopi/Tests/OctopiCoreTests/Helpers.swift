import Foundation
import Testing
@testable import OctopiCore

/// Generates CoreMotion-like samples for a person walking at 1.8 steps per second.
/// Device "forward" (+y) points along `deviceHeading`; the body accelerates along `walkHeading`.
struct WalkSimulator {
    var rate = 100.0
    var cadence = 1.8
    var time = 0.0
    var samples: [MotionSample] = []

    /// Quaternion whose device +y axis points at `heading` (radians CCW from east) in the xTrueNorthZVertical frame.
    static func attitude(heading: Double) -> Quaternion {
        let phi = heading - .pi
        return Quaternion(x: 0, y: 0, z: sin(phi / 2), w: cos(phi / 2))
    }

    /// Reference-frame vector for a world east/north/up vector (inverse of `Sample.map`).
    static func reference(east: Double, north: Double, up: Double) -> Vec3 { Vec3(x: north, y: -east, z: up) }

    mutating func walk(seconds: Double, walkHeading: Double, deviceOffset: Double = 0, yawRate: Double = 0, still: Bool = false) {
        let count = Int(seconds * rate)
        for _ in 0..<count {
            let heading = walkHeading + yawRate * (time - (time.rounded(.down)))
            _ = heading
            let deviceHeading = walkHeading + deviceOffset
            let q = Self.attitude(heading: deviceHeading)
            let phase = 2 * .pi * cadence * time
            let bob = still ? 0.0 : 2 + 2 * sin(phase)
            let forward = still ? 0.0 : 1.5 * sin(phase)
            let worldAccel = Self.reference(east: forward * cos(walkHeading), north: forward * sin(walkHeading), up: bob)
            let device = q.quat.inverseRotate(worldAccel)
            samples.append(MotionSample(
                elapsed: time,
                attitude: q,
                userAcceleration: Vector3(x: device.x, y: device.y, z: device.z),
                rotationRate: Vector3(x: 0, y: 0, z: yawRate),
                gravity: Vector3(x: 0, y: 0, z: -1),
                magneticField: .zero,
                magneticAccuracy: -1
            ))
            time += 1 / rate
        }
    }

    /// Turn in place by `angle` radians over `seconds`, updating the walk heading as we go.
    mutating func turn(by angle: Double, seconds: Double = 1.0, from heading: inout Double) {
        let count = Int(seconds * rate)
        let rate = angle / seconds
        for _ in 0..<count {
            heading += rate / self.rate
            let q = Self.attitude(heading: heading)
            samples.append(MotionSample(elapsed: time, attitude: q, userAcceleration: Vector3(x: 0, y: 0, z: 0.1), rotationRate: Vector3(x: 0, y: 0, z: rate)))
            time += 1 / self.rate
        }
    }

    mutating func stand(seconds: Double, heading: Double) {
        walk(seconds: seconds, walkHeading: heading, still: true)
    }
}

final class FakeHaptics: HapticOutput {
    var isAvailable = true
    var played: [(HapticPattern, Int?)] = []
    var stops = 0
    func play(_ pattern: HapticPattern, parameterMs: Int?) { played.append((pattern, parameterMs)) }
    func stop() { stops += 1 }
    var patterns: [HapticPattern] { played.map(\.0) }
}

final class FakePhone: PhoneMotionSource {
    var positions: [(Double, LocalPoint)] = []
    var walked: Double = 0
    var moving = true
    func position(at time: Double) -> LocalPoint {
        positions.last { $0.0 <= time }?.1 ?? .origin
    }
    func distanceWalked(from start: Double, to end: Double) -> Double { walked }
    func isMoving(at time: Double) -> Bool { moving }
}

func fix(lat: Double = 42.3601, lon: Double = -71.0942, accuracy: Double = 5, at date: Date, course: Double? = nil) -> GeoFix {
    GeoFix(latitude: lat, longitude: lon, horizontalAccuracy: accuracy, timestamp: date, course: course)
}

func approx(_ a: Double, _ b: Double, tolerance: Double) -> Bool { abs(a - b) <= tolerance }

let east = 0.0
let north = Double.pi / 2
let west = Double.pi
let south = -Double.pi / 2
