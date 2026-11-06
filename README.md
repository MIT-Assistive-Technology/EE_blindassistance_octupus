# EE_blindassistance_octupus
Electrical Engineering/Hardware Side of Blind Assistance! [Team Octupus!]

## What is here

| Folder | What |
|---|---|
| `PCB_Wristband/` | KiCad project for the haptic wristband |
| `lamb_v2/` | **Lamb (v2)**, the IMU logging / dead-reckoning test app (branch `imu-test-code`). Do not edit from the Octopi work; it is our test setup. |
| `Package.swift`, `Octopi/Sources/OctopiCore` | **OctopiCore**, the product app's logic as a Swift package. It compiles the step/heading pipeline from `lamb_v2/Path Construction` unmodified, plus anchors, paths, RSSI, left-behind detection, navigation, haptics and the session coordinator. |
| `Octopi/Tests/OctopiCoreTests` | Unit tests for the core (Swift Testing) |
| `Octopi/App`, `Octopi/Octopi.xcodeproj` | **Octopi**, the accessible iOS app (SwiftUI) |
| `Octopi/UITests` | XCUITest that runs Apple's accessibility audit on every screen |
| `scripts/a11y_lint.py` | Static accessibility lint for the SwiftUI sources |
| `docs/PLAN.md` | Architecture and module plan |
| `docs/ACCESSIBILITY.md` | Accessibility rules, vocabulary, checks |
| `docs/HARDWARE_INTERFACE.md` | Assumptions about band and beacon, and the BLE contract firmware must implement |
| `docs/PACKS.md`, `docs/sample-pack.json` | The shareable "pack of paths" file format and a sample |

## Build and test

Core logic tests (macOS, no simulator needed):

```bash
swift test
```

Open the app in Xcode: `Octopi/Octopi.xcodeproj`, scheme `Octopi`. Or from the command line:

```bash
xcodebuild -project Octopi/Octopi.xcodeproj -scheme Octopi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```

Accessibility checks:

```bash
python3 scripts/a11y_lint.py Octopi/App
```

```bash
xcodebuild -project Octopi/Octopi.xcodeproj -scheme Octopi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:OctopiUITests test
```

In the iOS simulator the app runs with a **hardware simulator** (band, beacons, walking, GPS) so
the whole flow can be tried without hardware: Settings → Simulator controls. On a real phone the
simulator is off unless launched with `-simulateHardware`.
