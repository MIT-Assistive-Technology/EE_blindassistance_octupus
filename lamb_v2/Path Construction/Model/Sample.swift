import Darwin
import Foundation

struct Sample {
    var elapsed: Double
    var isPath: Bool
    var quaternion: Quat
    var deviceUserAcceleration: Vec3
    var deviceRotation: Vec3
    var deviceGravity: Vec3
    var magneticField: Vec3
    var magneticAccuracy: Double
    var eastAcceleration: Double
    var northAcceleration: Double
    var upAcceleration: Double
    var yawRate: Double
    var heading: Double
    var pedometerSteps: Double
    var pedometerDistance: Double

    var accelerationMagnitude: Double { deviceUserAcceleration.length }

    var magneticIsUsable: Bool {
        guard Stats.Heading.useMagnetometer, magneticAccuracy >= Stats.Heading.minimumMagneticAccuracy else { return false }
        let strength = magneticField.length
        guard strength > 0 else { return false }
        return abs(strength - Stats.Heading.expectedField) / Stats.Heading.expectedField <= Stats.Heading.disturbanceRatio
    }

    static func map(_ reference: Vec3) -> (east: Double, north: Double, up: Double) {
        (-reference.y, reference.x, reference.z)
    }

    static func world(user: Vec3, rotation: Vec3, quaternion: Quat) -> (east: Double, north: Double, up: Double, yawRate: Double, heading: Double) {
        let accel = map(quaternion.rotate(user))
        let rate = map(quaternion.rotate(rotation))
        let forward = map(quaternion.rotate(Vec3(x: 0, y: 1, z: 0)))
        let heading = atan2(forward.north, forward.east) + Stats.Heading.forwardOffset
        return (accel.east, accel.north, accel.up, rate.up, HeadingMath.wrap(heading))
    }
}
