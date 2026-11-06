# Octopi app plan

Octopi remembers where you have been and guides you back by touch. This document is the
engineering plan for the phone app. It is written for the whole team, including people
who will only ever touch the hardware side.

The IMU test app in `lamb_v2/` (branch `imu-test-code`) is **not changed** by this work.
Its pedestrian-dead-reckoning (PDR) sources are compiled, unmodified, into the Octopi core
module so that tuning done in the test app flows straight into the product app.

## 1. Where things live

```
Package.swift                      Swift package `OctopiCore` (pure logic, no UI, runs on macOS for tests)
Octopi/Sources/OctopiCore/         Octopi logic: anchors, PDR wrapper, paths, RSSI, left-behind,
                                   navigation, haptic vocabulary, wearable/beacon protocols, session
Octopi/Tests/OctopiCoreTests/      Unit tests (Swift Testing). Run with `swift test` at the repo root.
Octopi/App/                        iOS app sources (SwiftUI + CoreMotion/CoreLocation/CoreBluetooth)
Octopi/Octopi.xcodeproj            Xcode project: app target `Octopi` + `OctopiUITests` (accessibility audit)
docs/PLAN.md                       This plan
docs/ACCESSIBILITY.md              Accessibility rules, checklist and how the checks are run
docs/HARDWARE_INTERFACE.md         Assumptions about the band/beacon and the exact BLE contract
lamb_v2/Path Construction/         IMU/PDR pipeline shared with the test app (read-only here)
```

Only these files from `lamb_v2/Path Construction` are compiled into `OctopiCore`:
`Model/{Sample,Geometry,StepFinder,GyroIntegrator,PathLine,Stats}.swift` and
`Steps/{StepWalk,StepTrail,HeadingHistory,StepLengthModel,TurnDetector}.swift`.
Everything else (Kalman filters, offline optimisers, plotting) stays test-app only.

## 2. Two modes, from the co-design sessions

| Mode | Who computes | Needs phone? | What the user feels |
|---|---|---|---|
| **Simple mode** | Band firmware only | No | Band locks onto the nearest paired beacon and pulses faster as RSSI rises (an "ADF" that beeps you home). Used at the pool, in the restaurant. |
| **Path mode** | Phone app | Yes, in pocket | Phone records a PDR path from a GPS anchor, drops pins, detects left-behind beacons, and streams turn-by-turn haptics to the band. |

The app implements Path mode and the setup/tutorial for both. Simple mode is firmware
(see `docs/HARDWARE_INTERFACE.md`); the app still shows its state and lets the user pick
which beacon the band should lock onto.

## 3. Core modules (`OctopiCore`)

Each module is a plain Swift type with injected time and no framework dependencies, so it
is unit-tested on macOS without a phone.

| Module | File(s) | Responsibility |
|---|---|---|
| Models | `Models/*.swift` | `GeoFix`, `Anchor`, `LocalPoint`, `Waypoint`, `StoredPath`, `Place` (a saved pin or beacon), `Confidence` |
| Geo math | `Geo/GeoMath.swift` | Haversine distance, bearing, east/north offsets, heading conventions (PDR uses radians CCW from east; compass uses degrees CW from north) |
| Anchor manager | `Anchor/AnchorManager.swift` | Decides whether a GPS fix is trustworthy (accuracy, age, plausibility vs. previous fix, consistency with PDR), keeps the last good anchor, re-anchors opportunistically and tells PDR to reset |
| Dead reckoner | `PDR/DeadReckoner.swift` | Wraps the shared step detector + gyro heading; outputs position relative to the anchor, heading, distance walked, "is the phone moving", and a drift estimate |
| Path recorder | `Path/PathRecorder.swift`, `Path/PathSimplifier.swift` | Turns PDR positions into a bounded waypoint list: points at every turn, one every ~3 m on straights (the "anchor points every 10 ft, denser at events" idea), Douglas-Peucker simplification, hard caps on count and length |
| RSSI | `Radio/RSSIFilter.swift`, `Radio/ProximityEstimator.swift` | Median + exponential smoothing per beacon, log-distance range estimate, zone (here/near/close/far/lost) and trend (approaching/receding) |
| Left-behind | `Radio/LeftBehindDetector.swift` | Per-beacon state machine using beacon motion flag, RSSI trend and phone motion; produces a left-behind event with the estimated position; snooze and hand-off ("someone else carries it") suppression |
| Beacon protocol | `Radio/BeaconAdvertisement.swift` | Parses the beacon's BLE manufacturer data (moving flag, seconds since motion, battery, tx power) |
| Wearable protocol | `Wearable/WearableProtocol.swift` | GATT UUIDs, command packet encoder, event decoder (button single/double/long, battery) |
| Haptics | `Haptic/HapticPattern.swift`, `Haptic/HapticVocabulary.swift` | The fixed vocabulary (ahead, left, right, turn around, arrived, pin confirmed, left-behind alert, proximity pulse, lost, low battery) as motor scripts for the 3-motor band and a single-motor fallback (phone) |
| Navigation | `Navigation/AnchorApproach.swift`, `Navigation/RouteFollower.swift`, `Navigation/NavigationSession.swift` | GPS leg to the anchor, waypoint following with PDR, RSSI proximity leg near a physical beacon, arrival; off-track recovery and "lost" fallback |
| Narrator | `Navigation/GuidanceNarrator.swift` | Short spoken phrases for VoiceOver/speech, rate-limited so the user is not talked over |
| Store | `Store/PlaceStore.swift` | Codable JSON persistence of places (in-memory version for tests) |
| Session | `Session/OctopiSession.swift` | The coordinator: feeds sensors to the modules, owns app state, emits announcements and haptic requests. The UI only talks to this |

## 4. The iOS app (`Octopi/App`)

* `Services/` adapters that turn CoreMotion, CoreLocation and CoreBluetooth into the core
  module's plain inputs, plus `PhoneHaptics` (CoreHaptics) and `Announcer` (VoiceOver
  announcements, falling back to speech when VoiceOver is off).
* `Views/` a deliberately small set of screens. One task per screen, one or two big
  buttons, everything readable by swiping in order:
  * Home: Drop a pin, Find, My places, Setup, Settings.
  * Find: list of places (most recent first) then a live guidance screen with one large
    status line, distance, and a Stop button.
  * Drop a pin: picks a name from a short list or dictation, confirms by haptic + voice.
  * Setup: permissions, pair band, pair beacons, haptic tutorial (feel each pattern).
  * Settings: left-behind sensitivity, snooze length, phone haptics mirror, Simple-mode beacon.
* The band's **record button** maps to: single press = drop a pin, double press = find
  the most recent place, long press = stop navigation / snooze alert. (Meeting 2 and 7 notes.)

## 5. Accessibility rules (summary; full list in `docs/ACCESSIBILITY.md`)

* Every control has a label, a hint and, where it changes, a value.
* Swipe order equals task order; the most important control is first.
* Touch targets are at least 60 pt tall; the primary action is 88 pt.
* Nothing is conveyed by colour alone; every state has text, haptics and speech.
* Dynamic Type up to accessibility sizes; layouts reflow, never truncate.
* Live guidance uses announcements, not a screen the user must read.
* Magic Tap (two-finger double tap) drops a pin or stops navigation.
* Checks: a static lint script over the SwiftUI sources, and an XCUITest that runs Apple's
  accessibility audit on each screen.

## 6. Delivery order

1. Core models, geo math, anchor manager, dead reckoner (with tests).
2. Path recorder/simplifier, RSSI, left-behind, protocols, haptics (with tests).
3. Navigation and session coordinator (with tests).
4. App: services, views, project file; builds for the iOS 26.2 simulator.
5. Accessibility lint + audit test.
6. Hardware interface document.

## 7. Decisions on the open questions

| Question | Decision for v1 |
|---|---|
| How do we know a GPS fix is good? | Accept only if reported accuracy ≤ 20 m, the implied speed from the previous fix is plausible, and the GPS displacement agrees with PDR displacement within the accuracy radius. Otherwise keep the old anchor and lower confidence. |
| Naming a manual pin | Band button pins get an automatic name ("Pin 3, 4:12 PM"); the app offers rename from a short list (Seat, Car, Bag, Door, Room) or dictation. |
| Multiple entrances | Guide to the stored anchor. If the user is outdoors with a good fix and the straight-line distance to the place's estimated global position is shorter than to the anchor, the narrator offers "direct" guidance to that estimate at lower confidence. |
| Floors | Not modelled. The record stores a barometric pressure delta if available; a large delta lowers confidence and the narrator says "this place may be on another floor". |
| Path cap | 200 waypoints or 400 m. Beyond the cap the oldest straight segments are thinned first; if still over, the record keeps the last 400 m and marks confidence low. |
| Stale anchors | Confidence decays after 6 hours; after 24 hours the narrator says "old pin, low confidence" before guiding. |
| False left-behind | Needs beacon stationary ≥ 10 s and phone walked ≥ 8 m away (or RSSI receding below threshold for 15 s). Snooze for 10 minutes with the band's long press. Hand-off mode suppresses alerts for that beacon. |
| Wearable disconnects mid-route | Phone haptics and speech continue; the app announces "band disconnected" once and reconnects automatically. |
