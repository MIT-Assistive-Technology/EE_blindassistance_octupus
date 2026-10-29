import Darwin
import Foundation

struct RauchSmoother: OfflinePath {
    let id = "h1"
    let name = "H1 Smoothed Kalman"

    func run(_ samples: [Sample]) -> PathLine {
        let filter = ExtendedKalman()
        filter.keepsHistory = true
        filter.reset()
        for sample in samples { filter.push(sample) }
        let history = filter.history
        guard history.count >= 2 else { return filter.line() }
        var smoothed = history.map(\.filtered)
        var index = history.count - 2
        while index >= 0 {
            let current = history[index]
            let next = history[index + 1]
            let gain = smootherGain(filtered: current.filteredCovariance, transition: next.transition, predicted: next.predictedCovariance)
            var delta = [Double](repeating: 0, count: 6)
            for axis in 0..<6 { delta[axis] = smoothed[index + 1][axis] - next.predicted[axis] }
            delta[4] = HeadingMath.wrap(delta[4])
            let correction = apply(gain, delta)
            for axis in 0..<6 { smoothed[index][axis] = current.filtered[axis] + correction[axis] }
            smoothed[index][4] = HeadingMath.wrap(smoothed[index][4])
            index -= 1
        }
        let originHeading = smoothed.first?[4] ?? Stats.Heading.initial
        var points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: originHeading)]
        for (offset, state) in smoothed.enumerated() {
            points.append(PathPoint(id: offset + 1, time: history[offset].time, east: state[0], north: state[1], heading: state[4]))
        }
        let last = smoothed.last ?? [0, 0, 0, 0, 0, 0]
        return PathLine(id: id, name: name, points: points, finalDisplacement: hypot(last[0], last[1]), maximumSpeed: filter.line().maximumSpeed, velocityDrift: hypot(last[2], last[3]), detail: "Offline smoother")
    }

    private func smootherGain(filtered: [Double], transition: [Double], predicted: [Double]) -> [Double] {
        let transposed = transpose(transition)
        let left = multiply(filtered, transposed)
        guard let inverse = invert(predicted) else { return [Double](repeating: 0, count: 36) }
        return multiply(left, inverse)
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

    private func apply(_ matrix: [Double], _ vector: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 6)
        for row in 0..<6 {
            var sum = 0.0
            for column in 0..<6 { sum += matrix[row * 6 + column] * vector[column] }
            result[row] = sum
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

    private func invert(_ matrix: [Double]) -> [Double]? {
        var a = matrix
        var inverse = [Double](repeating: 0, count: 36)
        for index in 0..<6 { inverse[index * 6 + index] = 1 }
        for pivot in 0..<6 {
            var best = pivot
            for row in (pivot + 1)..<6 where abs(a[row * 6 + pivot]) > abs(a[best * 6 + pivot]) { best = row }
            guard abs(a[best * 6 + pivot]) > 1e-10 else { return nil }
            if best != pivot {
                for column in 0..<6 {
                    a.swapAt(pivot * 6 + column, best * 6 + column)
                    inverse.swapAt(pivot * 6 + column, best * 6 + column)
                }
            }
            let scale = a[pivot * 6 + pivot]
            for column in 0..<6 {
                a[pivot * 6 + column] /= scale
                inverse[pivot * 6 + column] /= scale
            }
            for row in 0..<6 where row != pivot {
                let factor = a[row * 6 + pivot]
                for column in 0..<6 {
                    a[row * 6 + column] -= factor * a[pivot * 6 + column]
                    inverse[row * 6 + column] -= factor * inverse[pivot * 6 + column]
                }
            }
        }
        return inverse
    }
}
