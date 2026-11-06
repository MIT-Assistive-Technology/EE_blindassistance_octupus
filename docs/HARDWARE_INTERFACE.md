# Hardware interface and assumptions

This is the contract between the Octopi phone app and the two devices the EE team is building:
the **haptic band** (wrist) and the **beacon** (puck). It lists what the app assumes about each,
the exact Bluetooth messages, and what firmware has to do. Anything not listed here is not
needed by the app.

Source of truth for message formats in code: `Octopi/Sources/OctopiCore/Wearable/WearableProtocol.swift`
(band) and `Octopi/Sources/OctopiCore/Radio/BeaconAdvertisement.swift` (beacon). Both have
encode/decode unit tests; firmware can be checked against the byte sequences in
`Octopi/Tests/OctopiCoreTests/ProtocolAndHapticTests.swift`.

## 1. System picture

```
   Beacon (puck, on keys/bag)            Phone (iOS app)                 Band (wrist)
   BLE advertiser, accelerometer   --->  scans adverts, RSSI filter      <--- BLE peripheral
   "I am still / moving, battery"        PDR from phone IMU              button events
                                         GPS anchors, path memory        band ---> phone
                                         left-behind detection           phone ---> band
                                         haptic commands  -------------> plays patterns
                                                                        Simple mode: band scans
   Beacon  <----------------------------------------------------------  beacons by itself
```

Two modes (from the co-design sessions):

* **Path mode** (phone present): everything above. The band is a dumb output plus two buttons.
* **Simple mode** (no phone, e.g. at the pool): the band scans for the chosen beacon's advertisement
  and pulses by RSSI on its own. The app only tells the band which beacon serial to lock onto.

## 2. What the app assumes about the band

Taken from the KiCad schematic in `PCB_Wristband/` and the meeting notes.

| Assumption | Where it comes from | What breaks if wrong |
|---|---|---|
| ESP32-C3/S3 SuperMini running a BLE **peripheral** with the GATT service below | schematic (`ESP32-C3_SUPERMINI`, `ESP32-S3-SuperMini`) | nothing connects |
| **Three** haptic motors driven by three DRV2605L behind a TCA9548A I²C mux, laid out **left, centre, right** across the wrist | schematic (3× `DRV2605LDGS`, `TCA9548ARGER`, 3 motors) | directions lose their side cue; the single-motor vocabulary still works (count-coded) |
| **Two** tactile buttons (`PTS526` ×2): one **power**, one **record** | meeting 7 notes | the record button drives pin / find / stop; see §4 |
| Band reports battery and charging over the status characteristic | TP4056 charger on the board | no low-battery warning for the band |
| BNO055 IMU on the band is **not** used by the app in v1 | schematic | none; it is a future heading source (wrist heading is cleaner than a phone in a pocket) |
| Band reconnects automatically when it comes back in range of a bonded phone | — | user must re-pair after every disconnect |
| Band is a BLE **central** too, in Simple mode only, scanning for beacons | meeting 6 ("dumb mode") | Simple mode does not exist |

The app sends an **8–12 byte** command per haptic event, at most a few per second during the
proximity leg. The band never needs the path, the map or anything else.

## 3. Band GATT contract

Service UUID `6F637470-6900-4F63-746F-706900000001`. Advertise it, and a local name starting with
`Octopi Band` (e.g. `Octopi Band 1A2B`). Use a random static address or a fixed public one; the app
remembers the peripheral identifier after the first connection.

| Characteristic | UUID (…0900000000**xx**) | Properties | Payload |
|---|---|---|---|
| Command (phone → band) | `…0002` | write without response (write with response also accepted) | see Commands |
| Event (band → phone) | `…0003` | notify | see Events |
| Status (band → phone) | `…0004` | read, notify | `[battery %, charging 0/1, mode, fw major, fw minor]` |

### Commands (first byte is the opcode)

| Opcode | Name | Bytes after opcode | Meaning |
|---|---|---|---|
| `0x01` | play | `pattern, intensity(0–100), repeat, interval_lo, interval_hi` | Play pattern. `repeat = 0` means repeat until `stop`. `interval` (ms, little-endian) is used by the proximity pulse only. A new `play` replaces whatever is playing. |
| `0x02` | stop | — | Stop all motors. |
| `0x03` | setMode | `mode` | `0` idle, `1` path (phone drives), `2` simple (band drives). |
| `0x04` | setSimpleTarget | `serial (u32 LE)` | Which beacon Simple mode locks onto. `0` = strongest paired beacon. |
| `0x05` | ping | — | Reply with ack. |

Example: turn left at full intensity once: `01 03 64 01 00 00`.

### Pattern IDs and timings

Timings come from `HapticVocabulary.script(for:layout:.threeMotor)`; the firmware may store
them as tables. `L`/`C`/`R` = left/centre/right motor, `all` = all three.

| ID | Pattern | Script (ms on / ms gap) |
|---|---|---|
| `0x01` | pin confirmed | C 90/110, C 90 |
| `0x02` | ahead | C 450 |
| `0x03` | left | L 90/110 ×2 |
| `0x04` | right | R 90/110 ×3 |
| `0x05` | turn around | L 450/110, R 90/110, L 450 |
| `0x06` | arrived | L 90/40, C 90/40, R 90/120, all 700 |
| `0x07` | left-behind alert | all 400/300 ×4, repeated 3× (or until stop when repeat = 0) |
| `0x08` | proximity pulse | C 60, then gap so the period equals `interval` (min 150 ms); repeats until stop |
| `0x09` | signal lost | L+R 450/400 ×2, weak |
| `0x0A` | low battery | C 60/140 ×3, faint |
| `0x0B` | band connected | C 90 |
| `0x0C` | error | L+R 90/80 ×2 |

Intensities are 0–100; the app sends 100 and expects the DRV2605L library effect or PWM level
to map linearly. Blind testers will tune these; keep them in a table.

### Events (first byte is the type)

| Type | Name | Bytes after type | Meaning |
|---|---|---|---|
| `0x10` | button | `button (1 record, 2 power), action (1 single, 2 double, 3 long)` | Debounced on the band. Double = second press within 400 ms. Long = held ≥ 800 ms (fires once on release or at 800 ms, your choice). Send only one event per gesture. |
| `0x11` | battery | `percent, charging` | On change, at most once a minute. |
| `0x12` | ack | `opcode, status (0 ok)` | Optional; the app ignores failures but logs them. |
| `0x13` | modeChanged | `mode` | When the band changes mode on its own (e.g. power button long press toggles Simple mode). |
| `0x14` | simpleLock | `serial (u32 LE), rssi (int8)` | Simple mode: which beacon the band is locked onto; send on lock and every ~5 s. |

### Button mapping the app implements (record button)

| Gesture | Path mode (phone) | Simple mode (band alone) |
|---|---|---|
| single | drop a pin here (band gets `pinConfirmed`) | start/stop homing |
| double | guide me to the most recent place | cycle to next paired beacon |
| long | snooze a left-behind alert, else stop guidance | — |

Power button: on/off, and a long press toggles Simple mode. The app never acts on power-button events.

## 4. Simple mode firmware behaviour (band only)

1. Scan for beacon advertisements with the Octopi service UUID; parse manufacturer data (§6).
2. Lock onto the target serial (or the strongest paired one if target is 0).
3. Median-of-7 then exponential smoothing (alpha 0.3) of RSSI, exactly as `RSSIFilter` does.
4. Distance estimate `d = 10^((txPowerAt1m - rssi) / (10 × 2.4))`.
5. Pulse period = linear from 250 ms at ≤ 1.2 m to 2000 ms at ≥ 8 m (`ProximityEstimator`).
6. No advertisement for 10 s: play `signal lost` once, keep scanning.
7. ≤ 1.2 m for 3 s: play `arrived`, stop homing.

Doing this on the band gives the same feel as the phone's proximity leg.

## 5. What the app assumes about the beacon

| Assumption | Why it matters |
|---|---|
| BLE **advertiser only**; no connection needed | battery life, simplicity, many beacons at once |
| Advertises the beacon service UUID `6F637470-6900-4F63-746F-706900000010` **in the advertisement packet**, and the 14-byte manufacturer data below in the advertisement or scan response | iOS can only scan in the **background** for known service UUIDs; without it, left-behind detection only works while the app is on screen |
| Advertising interval 100–250 ms in the foreground use case; ≤ 1 s is acceptable | the RSSI filter wants ~4 readings in 10 s to compute a trend |
| An accelerometer sets the **moving** flag and a **seconds-since-last-motion** counter | this is the core left-behind signal; without it the app falls back to RSSI trend only |
| Motion threshold: any sustained movement a person makes while walking with the beacon in a pocket or bag counts as moving; sitting it on a table for 5 s counts as still | tune so that a beacon carried in a bag does not look "still" |
| Calibrated `txPowerAt1m` (measured RSSI at 1 m, stored in the advert) | range estimates and the pulse rate depend on it |
| Battery percent (or at least the low flag at ~15%) | low-battery warning |
| Transmit power: enough for 15–25 m indoors (0 dBm on ESP32 is fine) | range of the proximity leg |
| Serial number unique per unit, fixed for life | it is the identity in the app's records |

A button on the beacon is optional (flag bit 2). If present, pressing it could make the band buzz
("find my band") in a future version.

## 6. Beacon advertisement format (manufacturer-specific data, 14 bytes, little-endian)

| Offset | Field | Notes |
|---|---|---|
| 0–1 | company id | `0xFFFF` (test id) until we have a Bluetooth SIG id |
| 2 | magic | `0x4F` |
| 3 | version | `0x01` |
| 4–7 | serial | uint32 |
| 8 | flags | bit0 moving now, bit1 battery low, bit2 button pressed, bit3 charging |
| 9 | battery percent | 0–100, `0xFF` unknown |
| 10–11 | seconds since last motion | uint16, `0xFFFF` unknown; saturate at 65534 |
| 12 | tx power at 1 m | int8 dBm |
| 13 | sequence | increments every advertisement |

Example for serial 7, moving, 80 %, calibrated −59 dBm: `FF FF 4F 01 07 00 00 00 01 50 00 00 C5 2A`.

## 7. What the phone provides and assumes about itself

* iPhone 13 or newer on iOS 17+ (all four iPhones on the tester list qualify). The Samsung Galaxy
  S20 on the list is **not** covered: this app is iOS only.
* Motion (CoreMotion device motion at 100 Hz, true-north frame), location (CoreLocation),
  Bluetooth (CoreBluetooth central), optional barometer, CoreHaptics (fallback when the band is away).
* Background: the app declares `bluetooth-central` and `location` background modes. Left-behind
  detection in the background needs the beacon service UUID in the advert (§5) and the user to
  grant "Always" location (we start with "While Using"; upgrading is a settings step).
* **Heading limitation.** The shared PDR pipeline uses the phone's own yaw as the walking
  direction, i.e. it assumes the phone points forward (how the IMU test app is used). In a pocket
  the phone can point anywhere. `DeadReckoner` has an experimental `walkingAxis` heading source
  that estimates the walking direction from the horizontal acceleration pattern; it passes its
  unit test on synthetic data and should be validated on the Oct 29 experiment logs before being
  switched on. The band's BNO055 is the long-term fix: wrist yaw can be sent as an extra event.

## 8. Decisions needed from the hardware team

1. Confirm motor placement is left / centre / right across the wrist (the vocabulary depends on it).
2. Confirm the record button supports double and long presses in firmware (debounce timings above).
3. Pick whether the beacon's service UUID goes in the advert and the manufacturer data in the
   scan response (31-byte limit: 128-bit UUID = 18 bytes + 14 + 2 header bytes is too much for one packet).
4. Measure and store `txPowerAt1m` per beacon during manufacturing, or expose it via a calibration
   step in the app (hold the beacon at 1 m, press calibrate).
5. Decide beacon motion thresholds and the "still" timer with real pockets and bags.
6. Battery-low thresholds for both devices.

## 9. Tests the hardware team should run for the app

* **RSSI vs distance** at 0.5, 1, 2, 4, 8, 12 m, indoors with a person between phone and beacon.
  This sets `pathLossExponent` (currently 2.4) and the zone thresholds.
* **Motion flag latency**: pick the beacon up and put it down; how long until flags change.
* **Background scan rate** on an iPhone with the screen off (iOS coalesces duplicates; we need
  at least one reading every few seconds).
* **Haptic distinguishability** with Scott and Eric: can they tell left (2 taps) from right (3 taps)
  and turn-around from arrived, blind, without looking, on the first day.
* **Button gestures**: double and long press detection reliability through the silicone band.
