import XCTest

@MainActor final class TransitUITests: XCTestCase {
    private func launch(_ screen: String, reduced: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-snapshot", screen] + (reduced ? ["--reduce-effects"] : [])
        app.launch()
        return app
    }

    func testSavedBoardingPointOpensETAAndTrackingSheet() {
        let app = launch("home")
        let toggle = app.buttons["boarding.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
        toggle.tap() // Reversal must remain usable.
        let open = app.buttons["boarding.open"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let tracking = app.buttons["tracking.open"]
        for _ in 0..<4 where !tracking.isHittable { app.swipeUp() }
        XCTAssertTrue(tracking.waitForExistence(timeout: 5))
        tracking.tap()
        XCTAssertTrue(app.buttons["tracking.done"].waitForExistence(timeout: 5))
        app.buttons["tracking.done"].tap()
        XCTAssertTrue(tracking.waitForExistence(timeout: 5))
        screenshot("boarding-to-arrival")
    }

    func testTimelineCanSelectAndReverseWithReducedEffects() {
        let app = launch("route", reduced: true)
        let stop = app.buttons["route.stop.0"]
        for _ in 0..<3 where !stop.isHittable { app.swipeUp() }
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.buttons["route.stop.0"].waitForExistence(timeout: 5))
        let expanded = expectation(for: NSPredicate(format: "value == %@", "已展開"), evaluatedWith: stop)
        wait(for: [expanded], timeout: 5)
        stop.tap()
        XCTAssertTrue(stop.exists)
        let collapsed = expectation(for: NSPredicate(format: "value == %@", "已收起"), evaluatedWith: stop)
        wait(for: [collapsed], timeout: 5)
        screenshot("timeline-reduced-effects")
    }

    func testEmptyAndNetworkFailureAreVisible() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["下一班車，一目了然"].waitForExistence(timeout: 10))
        app.terminate()
        let failed = launch("error")
        XCTAssertTrue(failed.staticTexts["網絡中斷 · 上次資料"].waitForExistence(timeout: 10))
        XCTAssertTrue(failed.staticTexts["上次預測"].exists)
        screenshot("network-failure")
    }

    func testSystemActivityCanStartAndEndWhenAuthorized() throws {
        let app = launch("eta")
        let open = app.buttons["tracking.open"]
        for _ in 0..<4 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let start = app.buttons["tracking.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        for _ in 0..<3 where !start.isHittable { app.swipeUp() }
        start.tap()
        let disabled = app.staticTexts["請先在 iOS 設定中允許此 App 的實時活動。"]
        if disabled.waitForExistence(timeout: 2) {
            throw XCTSkip("This simulator disables ActivityKit authorization; signed-device lifecycle remains required")
        }
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["tracking.done"])
        wait(for: [dismissed], timeout: 10)
        XCTAssertFalse(app.descendants(matching: .any)["tracking.error"].exists)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        // Home's closing animation outlives the accessibility foreground event.
        Thread.sleep(forTimeInterval: 2)
        screenshot("activity-system-compact")
        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.name = "system-activity-accessibility-tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        app.activate()
        open.tap()
        let end = app.buttons["tracking.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        for _ in 0..<3 where !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["tracking.start"].waitForExistence(timeout: 5), "System activity ended and reconciled")
        screenshot("activity-start-end")
    }

    func testArrivalHasAccessibleDescriptionsAndUnclippedText() throws {
        let app = launch("eta", reduced: true)
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        screenshot("arrival-accessibility-audit")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
