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
        stop.tap()
        XCTAssertTrue(stop.exists)
        screenshot("timeline-reduced-effects")
    }

    func testEmptyAndNetworkFailureAreVisible() {
        let app = launch("empty")
        XCTAssertTrue(app.staticTexts["下一班車，一目了然"].waitForExistence(timeout: 10))
        app.terminate()
        let failed = launch("error")
        XCTAssertTrue(failed.staticTexts["暫無有效預測"].waitForExistence(timeout: 10))
        screenshot("network-failure")
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
