import XCTest

/// Walks every screen with the hardware simulator on and runs Apple's accessibility audit on each.
@MainActor
final class OctopiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-simulateHardware"]
        app.launch()
    }

    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) throws {
        // The audit has a fixed internal timeout that a slow simulator can trip; one retry is enough.
        do {
            try runAudit(screen)
        } catch let error as NSError where error.localizedDescription.contains("Timed out") {
            try runAudit(screen)
        }
    }

    private func runAudit(_ screen: String) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            // Dynamic Type at the largest sizes legitimately clips some decorative icons in SF Symbols labels;
            // everything else must pass.
            let ignored = issue.auditType == .textClipped && issue.element?.elementType == .image
            if !ignored {
                NSLog("A11Y AUDIT [%@]: %@ — %@ (%@)", screen, issue.compactDescription, issue.detailedDescription, issue.element.map { "\($0)" } ?? "no element")
            }
            return ignored
        }
    }

    /// Rows at the bottom of the Settings form only exist once scrolled into view.
    private func settingsRow(_ label: String) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        if !query.exists { app.swipeUp(); app.swipeUp() }
        return query
    }

    private func finishSetup() throws {
        let next = app.buttons["setup.next"]
        var guardCount = 0
        while next.waitForExistence(timeout: 2), guardCount < 10 {
            try audit("setup step \(guardCount)")
            next.tap()
            guardCount += 1
        }
        try audit("setup last step")
        app.buttons["setup.finish"].tap()
    }

    func testSetupHomeAndEveryScreenPassAccessibilityAudit() throws {
        try finishSetup()
        XCTAssertTrue(app.buttons["home.dropPin"].waitForExistence(timeout: 3))
        try audit("home")

        app.buttons["home.dropPin"].tap()
        XCTAssertTrue(app.buttons["name.save"].waitForExistence(timeout: 3))
        try audit("drop pin")
        app.buttons["name.My seat"].tap()

        app.buttons["home.find"].tap()
        XCTAssertTrue(app.buttons["place.My seat"].waitForExistence(timeout: 3))
        try audit("places")
        app.buttons["place.My seat"].tap()
        XCTAssertTrue(app.buttons["place.guide"].waitForExistence(timeout: 3))
        try audit("place detail")
        app.buttons["place.guide"].tap()
        // A pin dropped without walking has an empty path, so guidance may already be in the Arrived state.
        let endButton = app.buttons.matching(NSPredicate(format: "identifier IN {'navigate.stop', 'navigate.done'}")).firstMatch
        XCTAssertTrue(endButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["navigate.status"].firstMatch.exists)
        try audit("navigate")
        endButton.tap()
        XCTAssertTrue(app.buttons["home.dropPin"].waitForExistence(timeout: 3))

        app.buttons["home.beacons"].tap()
        XCTAssertTrue(app.buttons["beacon.pair.4097"].waitForExistence(timeout: 5))
        try audit("beacons")
        app.buttons["beacon.pair.4097"].tap()
        XCTAssertTrue(app.buttons["name.Keys"].waitForExistence(timeout: 3))
        app.buttons["name.Keys"].tap()
        XCTAssertTrue(app.staticTexts["Keys"].waitForExistence(timeout: 3))
        try audit("beacons paired")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Practice the buzzes"].tap()
        XCTAssertTrue(app.buttons["tutorial.ahead"].waitForExistence(timeout: 3))
        app.buttons["tutorial.ahead"].tap()
        try audit("tutorial")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Left-behind alerts"].waitForExistence(timeout: 3))
        try audit("settings")
        let diagnostics = settingsRow("Diagnostics")
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 3))
        diagnostics.tap()
        XCTAssertTrue(app.staticTexts["Dead reckoning"].waitForExistence(timeout: 3))
        try audit("diagnostics")
    }

    func testEveryControlHasAnAccessibilityLabel() throws {
        try finishSetup()
        XCTAssertTrue(app.buttons["home.dropPin"].waitForExistence(timeout: 3))
        for button in app.buttons.allElementsBoundByIndex {
            XCTAssertFalse(button.label.trimmingCharacters(in: .whitespaces).isEmpty, "button without a label: \(button)")
        }
    }

    func testBandButtonDropsPinAndLeftBehindAlertAppears() throws {
        try finishSetup()
        app.buttons["Settings"].tap()
        let controls = settingsRow("Simulator controls")
        XCTAssertTrue(controls.waitForExistence(timeout: 3))
        controls.tap()
        XCTAssertTrue(app.buttons["sim.band.single"].waitForExistence(timeout: 3))
        app.buttons["sim.band.single"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["home.find"].tap()
        let pin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place.Pin 1'")).firstMatch
        if !pin.waitForExistence(timeout: 8) { NSLog("HIERARCHY %@", app.debugDescription) }
        XCTAssertTrue(pin.exists)
    }
}
