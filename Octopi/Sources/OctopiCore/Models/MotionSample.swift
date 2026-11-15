import Foundation

/// A 3-vector in the phone's device frame.
nonisolated public struct Vector3: Codable, Equatable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vector3(x: 0, y: 0, z: 0)
    @MainActor var vec: Vec3 { Vec3(x: x, y: y, z: z) }
}

/// A unit quaternion from the phone's attitude.
nonisolated public struct Quaternion: Codable, Equatable, Sendable {
    public var x: Double, y: Double, z: Double, w: Double
    public init(x: Double, y: Double, z: Double, w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public static let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)
    @MainActor var quat: Quat { Quat(x: x, y: y, z: z, w: w) }
}

/// One device-motion reading, as produced by the app from CoreMotion using the
/// `xTrueNorthZVertical` reference frame (the same frame the IMU test app logs).
///
/// Units: seconds, m/s² (user acceleration *without* gravity, already scaled by g),
/// rad/s, gravity as a unit vector, magnetic field in microtesla.
nonisolated public struct MotionSample: Codable, Equatable, Sendable {
    public var elapsed: Double
    public var attitude: Quaternion
    public var userAcceleration: Vector3
    public var rotationRate: Vector3
    public var gravity: Vector3
    public var magneticField: Vector3
    /// CoreMotion's magnetometer accuracy raw value (-1 uncalibrated ... 3 high); negative when unknown.
    public var magneticAccuracy: Double

    public init(elapsed: Double, attitude: Quaternion, userAcceleration: Vector3, rotationRate: Vector3, gravity: Vector3 = Vector3(x: 0, y: 0, z: -1), magneticField: Vector3 = .zero, magneticAccuracy: Double = -1) {
        self.elapsed = elapsed
        self.attitude = attitude
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.magneticField = magneticField
        self.magneticAccuracy = magneticAccuracy
    }

    /// Convert into the shared PDR pipeline's sample type.
    @MainActor var sample: Sample {
        let quat = attitude.quat
        let user = userAcceleration.vec
        let rotation = rotationRate.vec
        let world = Sample.world(user: user, rotation: rotation, quaternion: quat)
        return Sample(
            elapsed: elapsed, isPath: true, quaternion: quat,
            deviceUserAcceleration: user, deviceRotation: rotation, deviceGravity: gravity.vec,
            magneticField: magneticField.vec, magneticAccuracy: magneticAccuracy,
            eastAcceleration: world.east, northAcceleration: world.north, upAcceleration: world.up,
            yawRate: world.yawRate, heading: world.heading, pedometerSteps: 0, pedometerDistance: 0
        )
    }
}
