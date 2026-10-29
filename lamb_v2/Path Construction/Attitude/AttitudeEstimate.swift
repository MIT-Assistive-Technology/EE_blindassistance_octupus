import Darwin
import Foundation

struct AttitudeEstimate {
    var quaternion = Quat(x: 0, y: 0, z: 0, w: 1)
    private var integral = Vec3(x: 0, y: 0, z: 0)
    private var lastTime: Double?

    mutating func reset() {
        quaternion = Quat(x: 0, y: 0, z: 0, w: 1)
        integral = Vec3(x: 0, y: 0, z: 0)
        lastTime = nil
    }

    mutating func update(_ sample: Sample, proportional: Double, integralGain: Double) -> (east: Double, north: Double) {
        guard let last = lastTime else {
            lastTime = sample.elapsed
            quaternion = sample.quaternion
            return (sample.eastAcceleration, sample.northAcceleration)
        }
        let dt = sample.elapsed - last
        lastTime = sample.elapsed
        guard dt > 0, dt < Stats.Path.gapReset else { return accelerations(sample.deviceUserAcceleration) }
        let specific = Vec3(
            x: sample.deviceUserAcceleration.x + sample.deviceGravity.x * Stats.Path.gravity,
            y: sample.deviceUserAcceleration.y + sample.deviceGravity.y * Stats.Path.gravity,
            z: sample.deviceUserAcceleration.z + sample.deviceGravity.z * Stats.Path.gravity
        )
        var gyro = sample.deviceRotation
        let norm = specific.length
        if abs(norm - Stats.Path.gravity) < Stats.Attitude.gravityTolerance, norm > 0 {
            let measured = specific.scaled(1 / norm)
            let estimated = quaternion.inverseRotate(Vec3(x: 0, y: 0, z: -1))
            let error = measured.cross(estimated)
            integral = Vec3(x: integral.x + error.x * dt, y: integral.y + error.y * dt, z: integral.z + error.z * dt)
            gyro = Vec3(
                x: gyro.x + proportional * error.x + integralGain * integral.x,
                y: gyro.y + proportional * error.y + integralGain * integral.y,
                z: gyro.z + proportional * error.z + integralGain * integral.z
            )
        }
        let step = min(dt, Stats.Path.maximumDelta)
        quaternion = quaternion.integrated(gyro: gyro, dt: step)
        if sample.magneticIsUsable {
            let field = Sample.map(quaternion.rotate(sample.magneticField))
            let yawError = atan2(field.east, field.north)
            let correction = quaternion.inverseRotate(Vec3(x: 0, y: 0, z: -yawError * Stats.Attitude.magnetometerGain))
            quaternion = quaternion.integrated(gyro: correction, dt: step)
        }
        return accelerations(sample.deviceUserAcceleration)
    }

    private func accelerations(_ user: Vec3) -> (east: Double, north: Double) {
        let mapped = Sample.map(quaternion.rotate(user))
        return (mapped.east, mapped.north)
    }
}
