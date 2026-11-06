# Accessibility in the Octopi app

Our users are blind. The co-design notes (meeting 6) describe how they use a phone: VoiceOver,
everything serialized, flick right to the next item, double tap to activate, explore by touch.
No voice control. The phone stays in a pocket while walking, so **the screen is a backup; the
band and the voice are the interface.**

## Rules (every screen follows all of them)

1. **One task per screen.** Home has five buttons. Guidance has one status and one Stop.
2. **Swipe order is task order.** The most important control comes first in the reading order
   (`accessibilitySortPriority` on the left-behind banner).
3. **Every control has a label, a hint when the effect is not obvious, and a value when it changes.**
   Rows are single elements (`accessibilityElement(children: .combine/.ignore)`) that read as one sentence:
   "My seat. Pin, 5 minutes ago, confidence high, 30 metres away."
4. **Nothing is colour-only.** Every state is text plus a haptic plus a spoken announcement.
5. **Big targets.** Secondary buttons are at least 64 pt tall, the primary action 88 pt, full width.
6. **Dynamic Type everywhere.** Text styles only (lint forbids fixed sizes); layouts are vertical
   stacks that reflow; no single-line truncation.
7. **Headings are headings** (`.isHeader`) so the rotor can jump between screens' sections.
8. **Live guidance is announced, not displayed.** `OctopiSession` emits `Announcement`s; the
   `Announcer` posts them as VoiceOver announcements (with priority) and, when VoiceOver is off,
   speaks them with `AVSpeechSynthesizer` if the user enabled it. The guidance screen's status is
   one element marked `.updatesFrequently` and receives focus when the screen opens.
9. **Magic Tap** (two-finger double tap) drops a pin on Home and stops navigation on the guidance
   screen. **Escape** (two-finger scrub) also stops navigation.
10. **Confirm destruction.** Delete and Unpair use a confirmation dialog.
11. **Increase Contrast** thickens button borders (`colorSchemeContrast`); the accent colour has
    4.5:1 contrast against white in light mode and against black in dark mode.
12. **No timing traps.** Nothing auto-dismisses. Alerts stay until Find / Snooze / I have it.
13. **Naming without typing.** Quick-name lists come first; the text field is optional and the
    keyboard's microphone key gives dictation.
14. **No `Form`/`List` screens.** Their section headers, inline pickers and even plain rows fail
    Apple's contrast and Dynamic Type audits. Every screen is a `ScrollView` of stacked
    `ScreenHeading`, `SectionHeader`, `InfoRow`, `ChoiceRow`, `ToggleRow` and big buttons.

## Haptic and spoken vocabulary

| Pattern | Band (3 motors) | Phone / single motor | Spoken |
|---|---|---|---|
| Go straight | 1 long, centre | 1 long | "Straight ahead, 12 metres." |
| Turn left | 2 taps, left | 2 taps | "Turn left." |
| Turn right | 3 taps, right | 3 taps | "Turn right." |
| Turn around | long-short-long alternating sides | long-short-long | "Turn around." |
| Arrived | sweep left→centre→right then long all | rising triple then long | "You have arrived." |
| Pin saved | 2 quick taps | 2 quick taps | "Pin saved: My seat. Confidence high." |
| Left behind | 4 strong slow buzzes × 3 | same | "Keys may have been left behind, about 20 metres back…" |
| Getting closer | single taps, faster as RSSI rises | same | zone changes only: "Very close. Slow down and feel around." |
| Signal lost | 2 slow weak buzzes | same | "I lost the beacon's signal." |

Left and right differ in **count** as well as side, so the vocabulary survives on one motor.
The narrator never repeats itself more often than every 2.5 s, repeats "straight ahead, N metres"
every 8 s, and announces arrival exactly once.

## Automated checks

* **Static lint** `python3 scripts/a11y_lint.py Octopi/App` runs over the SwiftUI sources and fails
  on fixed font sizes, image-only buttons without labels, tap gestures on non-controls, single-line
  truncation, empty control labels, sub-44-pt controls and colour-only signals.
* **Runtime audit** `OctopiUITests` launches the app with the hardware simulator, walks setup → home →
  drop pin → places → place detail → guidance → beacons → pairing → tutorial → settings → diagnostics,
  and runs Apple's `performAccessibilityAudit(for: .all)` on each screen (contrast, Dynamic Type
  clipping, element descriptions, hit regions, traits, parent/child). It also asserts every button
  has a non-empty label and that a band button press creates a pin.

  ```bash
  xcodebuild -project Octopi/Octopi.xcodeproj -scheme Octopi -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:OctopiUITests test
  ```

* **Core logic tests** (`swift test`) cover the narrator's throttling, the spoken distance rounding,
  and the haptic vocabulary (every pattern has a script on both layouts, left/right differ on one motor).

## Manual VoiceOver checklist (do this with Scott and Eric)

1. Turn on VoiceOver. From Home, flick right through every element; nothing is skipped or read twice.
2. Double tap "Drop a pin here"; pick a quick name; hear the confirmation and feel two taps.
3. Two-finger double tap on Home drops a pin without opening anything.
4. Open Find a place; each row reads name, type, when, confidence, distance in one go.
5. Start guidance; the status element is focused and later updates are announced without
   touching the phone; two-finger double tap stops.
6. Set text size to the largest accessibility size; every screen still scrolls and reads fully.
7. Turn on Increase Contrast and Smart Invert; every button is still visible and readable.
8. Trigger a left-behind alert (Settings → Simulator controls → Leave Keys here, then Start walking);
   the banner is the first thing read on Home and its three buttons work.
9. Disconnect the band mid-route; the phone keeps vibrating and the announcement says so.

## Known gaps to close with testers

* The haptic patterns have not yet been felt by blind testers; the counts and timings in
  `HapticVocabulary` are a starting point to tune with them.
* Spoken distances assume metres by default; Settings switches to feet.
* The app has no audio cue when VoiceOver is off and speech is disabled; haptics carry everything then.
