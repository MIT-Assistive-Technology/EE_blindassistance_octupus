import Foundation

enum PathCatalog {
    static func makeOnline() -> [any OnlinePath] {
        [
            WorldAccelPath(id: "a1", name: "A1 Raw integration", detail: "No bias removed"),
            BiasCalibration(),
            StillPath(id: "a3", name: "A3 Still resets", detail: "Velocity resets"),
            FixedHeading(), GyroHeading(), CompassHeading(),
            CadenceLength(), WeinbergLength(),
            GyroIntegration(), TurnPath(), MagnetometerHeading(),
            WorldAccelPath(id: "e1", name: "E1 Core Motion attitude", detail: "True-north attitude"),
            TunedAttitude(id: "e2", name: "E2 Complementary attitude", detail: "Gyro with gravity tilt", proportional: Stats.Attitude.complementaryGain, integral: 0),
            TunedAttitude(id: "e3", name: "E3 Mahony attitude", detail: "Quaternion filter", proportional: Stats.Attitude.mahonyProportional, integral: Stats.Attitude.mahonyIntegral),
            StillPath(id: "f1", name: "F1 Stationary reset", detail: "Confident resets"),
            ExtendedKalman()
        ]
    }

    static func makeOffline() -> [any OfflinePath] {
        [RauchSmoother(), StepOptimizer()]
    }

    static let unavailable = [
        RegressionLength.slot, PersonalScale.slot, FootMount.slot,
        LoopClosure.slot, MapMatch.slot, NoCompanion.slot
    ]
}
