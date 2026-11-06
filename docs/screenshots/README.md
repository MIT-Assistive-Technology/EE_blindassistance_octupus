# Screenshots

Captured from the iOS simulator (iPhone 17, iOS 26.2) with the hardware simulator on.

| File | Screen |
|---|---|
| `01-setup-welcome.png` | First-run setup, step 1 of 5 |
| `02-home.png` | Home: status card and the five actions |
| `03-drop-pin.png` | Name picker shown after Drop a pin |
| `04-guidance.png` | Live guidance while walking back to a pin |
| `05-left-behind-alert.png` | Home with a left-behind alert for the Keys beacon |
| `06-find-a-place.png` | Find a place: search, filters, order, results, packs |
| `07-place-detail.png` | A place with Guide me there |
| `08-beacons.png` | Paired beacon card and a nearby unpaired beacon |
| `09-practice.png` | Practice the buzzes |
| `10-settings.png` | Settings |

To recapture, build the app for the simulator and launch it with the debug arguments
(`-skipSetup`, `-open=places|place|beacons|tutorial|settings|dropPin`,
`-demoWalk -demoScenario=navigate|alert`), then `xcrun simctl io booted screenshot <file>`.
