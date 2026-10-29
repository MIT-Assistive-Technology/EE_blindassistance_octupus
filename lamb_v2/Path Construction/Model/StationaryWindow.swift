import Foundation

final class StationaryWindow {
    private var times: [Double] = []
    private var magnitudes: [Double] = []
    private var gyros: [Double] = []

    func reset() { times.removeAll(); magnitudes.removeAll(); gyros.removeAll() }

    func push(_ sample: Sample) -> Double {
        guard sample.isPath else { return 0 }
        times.append(sample.elapsed)
        magnitudes.append(sample.accelerationMagnitude)
        gyros.append(sample.deviceRotation.length)
        while let first = times.first, sample.elapsed - first > Stats.Stationary.window {
            times.removeFirst(); magnitudes.removeFirst(); gyros.removeFirst()
        }
        guard let first = times.first, sample.elapsed - first >= Stats.Stationary.window * 0.8, magnitudes.count >= 3 else { return 0 }
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        var spread = 0.0
        for value in magnitudes { let delta = value - mean; spread += delta * delta }
        let variance = spread / Double(magnitudes.count)
        let gyro = gyros.reduce(0, +) / Double(gyros.count)
        let accelScore = max(0, 1 - variance / Stats.Stationary.accelerationVariance)
        let gyroScore = max(0, 1 - gyro / Stats.Stationary.gyroscopeLimit)
        return min(accelScore, gyroScore)
    }

    func isConfident(after sample: Sample) -> Bool {
        push(sample) >= Stats.Stationary.minimumConfidence
    }
}
