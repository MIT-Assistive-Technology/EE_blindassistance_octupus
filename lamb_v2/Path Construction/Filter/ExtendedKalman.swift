import Darwin
import Foundation

struct KalmanSnapshot {
    var filtered: [Double]
    var filteredCovariance: [Double]
    var predicted: [Double]
    var predictedCovariance: [Double]
    var transition: [Double]
    var time: Double
}

final class ExtendedKalman: OnlinePath {
    let id = "g"
    let name = "G Extended Kalman"
    private var state = KalmanState()
    private var finder = StepFinder()
    private var gyro = GyroIntegrator()
    private var window = StationaryWindow()
    private var lastTime: Double?
    private var points: [PathPoint] = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: 0)]
    private var nextID = 1
    private var maximumSpeed = 0.0
    private(set) var history: [KalmanSnapshot] = []
    var keepsHistory = false

    func reset() {
        state.reset(); finder.reset(); gyro.reset(); window.reset()
        lastTime = nil; nextID = 1; maximumSpeed = 0; history.removeAll()
        points = [PathPoint(id: 0, time: 0, east: 0, north: 0, heading: state.value[4])]
    }

    func push(_ sample: Sample) {
        guard sample.isPath else { return }
        let first = lastTime == nil
        let dt = lastTime.map { sample.elapsed - $0 } ?? 0
        lastTime = sample.elapsed
        if first {
            state.value[4] = sample.heading
            if !points.isEmpty { points[0].heading = sample.heading }
        }
        if dt > 0 {
            state.predict(east: sample.eastAcceleration, north: sample.northAcceleration, yawRate: sample.yawRate, dt: dt)
        }
        let predicted = state.value
        let predictedCovariance = state.covariance
        gyro.push(sample)
        if finder.push(sample) != nil {
            if !state.haveAnchor { state.anchorEast = state.value[0]; state.anchorNorth = state.value[1]; state.haveAnchor = true }
            let move = HeadingMath.step(length: Stats.Length.normal, heading: state.value[4])
            state.correct(index: 0, innovation: state.anchorEast + move.east - state.value[0], variance: Stats.Kalman.stepLengthVariance)
            state.correct(index: 1, innovation: state.anchorNorth + move.north - state.value[1], variance: Stats.Kalman.stepLengthVariance)
            state.anchorEast = state.value[0]; state.anchorNorth = state.value[1]
        }
        state.correct(index: 4, innovation: HeadingMath.wrap(gyro.heading - state.value[4]), variance: Stats.Kalman.gyroHeadingVariance)
        if sample.magneticIsUsable {
            state.correct(index: 4, innovation: HeadingMath.wrap(sample.heading - state.value[4]), variance: Stats.Kalman.compassVariance)
        }
        if window.isConfident(after: sample) {
            state.correct(index: 2, innovation: -state.value[2], variance: Stats.Kalman.stillVelocityVariance)
            state.correct(index: 3, innovation: -state.value[3], variance: Stats.Kalman.stillVelocityVariance)
        }
        if keepsHistory, dt > 0 {
            var transition = [Double](repeating: 0, count: 36)
            let step = min(dt, Stats.Path.maximumDelta)
            for index in 0..<6 { transition[index * 6 + index] = 1 }
            transition[2] = step; transition[9] = step; transition[29] = -step
            history.append(KalmanSnapshot(filtered: state.value, filteredCovariance: state.covariance, predicted: predicted, predictedCovariance: predictedCovariance, transition: transition, time: sample.elapsed))
        }
        maximumSpeed = max(maximumSpeed, hypot(state.value[2], state.value[3]))
        points.append(PathPoint(id: nextID, time: sample.elapsed, east: state.value[0], north: state.value[1], heading: state.value[4]))
        nextID += 1
    }

    func line() -> PathLine {
        PathLine(id: id, name: name, points: points, finalDisplacement: hypot(state.value[0], state.value[1]), maximumSpeed: maximumSpeed, velocityDrift: hypot(state.value[2], state.value[3]), detail: "Bias \(state.value[5]) rad/s")
    }
}
