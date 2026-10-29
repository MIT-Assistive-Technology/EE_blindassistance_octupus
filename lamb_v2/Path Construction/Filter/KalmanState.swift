import Foundation

struct KalmanState {
    var value = [Double](repeating: 0, count: 6)
    var covariance = KalmanState.initialCovariance()
    var anchorEast = 0.0
    var anchorNorth = 0.0
    var haveAnchor = false

    static func initialCovariance() -> [Double] {
        var matrix = [Double](repeating: 0, count: 36)
        let diagonal = [
            Stats.Kalman.initialPositionVariance, Stats.Kalman.initialPositionVariance,
            Stats.Kalman.initialVelocityVariance, Stats.Kalman.initialVelocityVariance,
            Stats.Kalman.initialHeadingVariance, Stats.Kalman.initialBiasVariance
        ]
        for index in 0..<6 { matrix[index * 6 + index] = diagonal[index] }
        return matrix
    }

    mutating func reset() {
        value = [0, 0, Stats.Path.initialEast, Stats.Path.initialNorth, Stats.Heading.initial, Stats.Heading.gyroBias]
        covariance = Self.initialCovariance()
        anchorEast = 0; anchorNorth = 0; haveAnchor = false
    }

    mutating func predict(east accelEast: Double, north accelNorth: Double, yawRate: Double, dt: Double) {
        let step = min(dt, Stats.Path.maximumDelta)
        value[0] += value[2] * step + 0.5 * accelEast * step * step
        value[1] += value[3] * step + 0.5 * accelNorth * step * step
        value[2] += accelEast * step
        value[3] += accelNorth * step
        value[4] = HeadingMath.wrap(value[4] + (yawRate - value[5]) * step)
        var transition = [Double](repeating: 0, count: 36)
        for index in 0..<6 { transition[index * 6 + index] = 1 }
        transition[0 * 6 + 2] = step
        transition[1 * 6 + 3] = step
        transition[4 * 6 + 5] = -step
        let predicted = multiply(transition, covariance)
        let transposed = transpose(transition)
        covariance = add(multiply(predicted, transposed), processNoise(step))
        symmetrize()
    }

    mutating func correct(index: Int, innovation: Double, variance: Double) {
        var gainColumn = [Double](repeating: 0, count: 6)
        for row in 0..<6 { gainColumn[row] = covariance[row * 6 + index] }
        let scale = variance + covariance[index * 6 + index]
        guard scale > 1e-9 else { return }
        for row in 0..<6 { value[row] += gainColumn[row] / scale * innovation }
        for row in 0..<6 {
            let factor = gainColumn[row] / scale
            for column in 0..<6 {
                covariance[row * 6 + column] -= factor * covariance[index * 6 + column]
            }
        }
        value[4] = HeadingMath.wrap(value[4])
        symmetrize()
    }

    private func processNoise(_ step: Double) -> [Double] {
        var noise = [Double](repeating: 0, count: 36)
        let accel = Stats.Kalman.accelerationNoise * step
        noise[2 * 6 + 2] = accel * accel
        noise[3 * 6 + 3] = accel * accel
        noise[4 * 6 + 4] = Stats.Kalman.headingProcessNoise * step
        noise[5 * 6 + 5] = Stats.Kalman.biasProcessNoise * step
        return noise
    }

    private mutating func symmetrize() {
        for row in 0..<6 {
            for column in (row + 1)..<6 {
                let mean = 0.5 * (covariance[row * 6 + column] + covariance[column * 6 + row])
                covariance[row * 6 + column] = mean
                covariance[column * 6 + row] = mean
            }
        }
    }

    private func multiply(_ left: [Double], _ right: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 36)
        for row in 0..<6 {
            for column in 0..<6 {
                var sum = 0.0
                for k in 0..<6 { sum += left[row * 6 + k] * right[k * 6 + column] }
                result[row * 6 + column] = sum
            }
        }
        return result
    }

    private func transpose(_ matrix: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 36)
        for row in 0..<6 {
            for column in 0..<6 { result[column * 6 + row] = matrix[row * 6 + column] }
        }
        return result
    }

    private func add(_ left: [Double], _ right: [Double]) -> [Double] {
        var result = left
        for index in result.indices { result[index] += right[index] }
        return result
    }
}
