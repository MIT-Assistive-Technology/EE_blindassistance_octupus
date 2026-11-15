import Darwin
import Foundation

struct Vec3 {
    var x: Double
    var y: Double
    var z: Double

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    func scaled(_ k: Double) -> Vec3 { Vec3(x: x * k, y: y * k, z: z * k) }

    func cross(_ o: Vec3) -> Vec3 {
        Vec3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
    }

    func unit() -> Vec3 {
        let n = length
        guard n > 0 else { return self }
        return scaled(1 / n)
    }
}

struct Quat {
    var x: Double
    var y: Double
    var z: Double
    var w: Double

    func rotate(_ v: Vec3) -> Vec3 {
        let n = (x * x + y * y + z * z + w * w).squareRoot()
        guard n > 0 else { return v }
        let x = self.x / n, y = self.y / n, z = self.z / n, w = self.w / n
        let tx = 2 * (y * v.z - z * v.y)
        let ty = 2 * (z * v.x - x * v.z)
        let tz = 2 * (x * v.y - y * v.x)
        return Vec3(
            x: v.x + w * tx + y * tz - z * ty,
            y: v.y + w * ty + z * tx - x * tz,
            z: v.z + w * tz + x * ty - y * tx
        )
    }

    func inverseRotate(_ v: Vec3) -> Vec3 {
        Quat(x: -x, y: -y, z: -z, w: w).rotate(v)
    }

    func normalized() -> Quat {
        let n = (x * x + y * y + z * z + w * w).squareRoot()
        guard n > 0 else { return self }
        return Quat(x: x / n, y: y / n, z: z / n, w: w / n)
    }

    func integrated(gyro: Vec3, dt: Double) -> Quat {
        let half = gyro.scaled(0.5 * dt)
        let spin = Quat(
            x: w * half.x + y * half.z - z * half.y,
            y: w * half.y + z * half.x - x * half.z,
            z: w * half.z + x * half.y - y * half.x,
            w: -x * half.x - y * half.y - z * half.z
        )
        return Quat(x: x + spin.x, y: y + spin.y, z: z + spin.z, w: w + spin.w).normalized()
    }
}

enum HeadingMath {
    static func wrap(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    static func blend(_ from: Double, _ to: Double, gain: Double) -> Double {
        wrap(from + gain * wrap(to - from))
    }

    static func step(length: Double, heading: Double) -> (east: Double, north: Double) {
        (length * cos(heading), length * sin(heading))
    }
}
