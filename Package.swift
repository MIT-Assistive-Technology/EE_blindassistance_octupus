// swift-tools-version: 6.2
// Octopi core logic package.
//
// The `OctopiCore` module compiles two source trees into one module:
//   * lamb_v2/Path Construction   -> the IMU / pedestrian-dead-reckoning pipeline
//                                    from the imu-test-code work (read-only, shared
//                                    with the Lamb (v2) IMU test app, never edited here)
//   * Octopi/Sources/OctopiCore   -> the Octopi app logic (anchors, beacons, RSSI,
//                                    left-behind detection, navigation, haptics)
//
// Run the unit tests from the repository root with:  swift test
import PackageDescription

let package = Package(
    name: "Octopi",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OctopiCore", targets: ["OctopiCore"])
    ],
    targets: [
        .target(
            name: "OctopiCore",
            path: ".",
            exclude: [
                "README.md", "docs", "PCB_Wristband", "Octopi/App", "Octopi/Tests", "Octopi/Octopi.xcodeproj",
                "lamb_v2/App", "lamb_v2/Views", "lamb_v2/IMU Logging", "lamb_v2/MyApp",
                "lamb_v2/Lamb--v2--Info.plist", "lamb_v2/lamb_v2.xcodeproj", "lamb_v2/lamb_v2-upload.xcodeproj",
                "lamb_v2/Path Construction/Later",
                "lamb_v2/Path Construction/Run",
                "lamb_v2/Path Construction/Score",
                "lamb_v2/Path Construction/Filter",
                "lamb_v2/Path Construction/Attitude",
                "lamb_v2/Path Construction/Integration",
                "lamb_v2/Path Construction/Steps/StepOptimizer.swift",
                "lamb_v2/Path Construction/Steps/FixedHeading.swift",
                "lamb_v2/Path Construction/Steps/StepPaths.swift",
                "lamb_v2/Path Construction/Steps/TurnPath.swift",
                "lamb_v2/Path Construction/Model/StationaryWindow.swift",
                "lamb_v2/Path Construction/Model/TrapezoidTrack.swift"
            ],
            sources: [
                "lamb_v2/Path Construction",
                "Octopi/Sources/OctopiCore"
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "OctopiCoreTests",
            dependencies: ["OctopiCore"],
            path: "Octopi/Tests/OctopiCoreTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
