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
        stop.tap()
        let eta = app.descendants(matching: .any)["route.eta.0"]
        for _ in 0..<3 where !eta.isHittable { app.swipeUp() }
        XCTAssertTrue(eta.waitForExistence(timeout: 5))
        eta.tap()
        XCTAssertTrue(app.buttons["tracking.open"].waitForExistence(timeout: 5), "Only the explicit ETA link navigates")
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

    func testSearchResultOpensTheMatchingRoute() {
        let app = launch("search-results")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.route.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["route.stop.0"].exists)
        screenshot("search-to-route")
    }

    func testSystemActivityCanStartAndEndWhenAuthorized() throws {
        try exerciseSystemActivity(screen: "eta", route: "1A", stop: "彌敦道")
    }

    func testEastRailSystemActivityRendersItsRouteAndBoardingStop() throws {
        try exerciseSystemActivity(screen: "eta-eal", route: "EAL", stop: "紅磡")
    }

    private func exerciseSystemActivity(screen: String, route: String, stop: String) throws {
        let app = launch(screen)
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
        let renderedRoute = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", route)).firstMatch
        XCTAssertTrue(renderedRoute.waitForExistence(timeout: 20),
                      "ActivityKit must render the route in the actual system Island")
        screenshot("activity-system-compact-\(route)")
        let hierarchy = XCTAttachment(string: springboard.debugDescription)
        hierarchy.name = "system-activity-accessibility-tree"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let island = springboard.otherElements.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "jindo-container-view:")).firstMatch
        XCTAssertTrue(island.exists)
        XCTAssertLessThan(island.frame.width, 300, "Compact fixture must not reserve an oversized empty region")
        island.press(forDuration: 1.2)
        let renderedStop = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", stop)).firstMatch
        XCTAssertTrue(renderedStop.waitForExistence(timeout: 10),
                      "Expanded Island must show the selected boarding stop")
        screenshot("activity-system-expanded-\(route)")
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

    func testDepartureBoardControlsAndRevisedDigitsStayStable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-snapshot", "eta", "--eta-motion-test"]
        app.launch()
        let digits = app.staticTexts["eta.primary-minutes"]
        XCTAssertTrue(digits.waitForExistence(timeout: 10))
        XCTAssertEqual(digits.label, "7")
        let pin = app.buttons["eta.pin"]
        XCTAssertEqual(pin.value as? String, "已選取")
        pin.tap()
        XCTAssertEqual(pin.value as? String, "未選取")
        pin.tap()
        app.buttons["eta.favorite"].tap()
        app.buttons["eta.favorite"].tap()
        let revise = app.buttons["eta.test.revise"]
        for _ in 0..<3 where !revise.isHittable { app.swipeUp() }
        revise.tap()
        let ten = expectation(for: NSPredicate(format: "label == %@", "10"), evaluatedWith: digits)
        wait(for: [ten], timeout: 5)
        let unit = app.staticTexts["eta.primary-unit"]
        let unitPosition = unit.frame.minX
        screenshot("eta-ten-minutes")
        revise.tap()
        let nine = expectation(for: NSPredicate(format: "label == %@", "9"), evaluatedWith: digits)
        wait(for: [nine], timeout: 5)
        XCTAssertEqual(unit.frame.minX, unitPosition, accuracy: 0.5, "10 to 9 must not shift the arrival column")
        screenshot("eta-nine-minutes")
        revise.tap()
        let revised = expectation(for: NSPredicate(format: "label == %@", "3"), evaluatedWith: digits)
        wait(for: [revised], timeout: 5)
        XCTAssertEqual(app.staticTexts.matching(identifier: "eta.primary-minutes").count, 1,
                       "A revised ETA retains one stable digit view")
        screenshot("eta-revised-digits")
    }

    func testArrivalHasAccessibleDescriptionsAndUnclippedText() throws {
        let app = launch("eta", reduced: true)
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        screenshot("arrival-accessibility-audit")
    }

    func testTodayTrackingSurfaceNavigatesAndRemainsReadableWithReducedEffects() throws {
        let app = launch("home-tracking-eal", reduced: true)
        let open = app.buttons["home.tracking.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.tracking.menu"].exists)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        screenshot("today-tracking-reduced-effects")
        open.tap()
        XCTAssertTrue(app.navigationBars["EAL"].waitForExistence(timeout: 5))
    }

    func testTodayTrackingShowsReadableDepartureAndStaleState() {
        let app = launch("home-tracking-eal")
        XCTAssertTrue(app.buttons["home.tracking.open"].waitForExistence(timeout: 10))
        screenshot("today-tracking-departure-card")
        app.terminate()
        let stale = launch("home-tracking-stale")
        XCTAssertTrue(stale.buttons["home.tracking.open"].waitForExistence(timeout: 10))
        XCTAssertTrue(stale.staticTexts["預測已過期"].exists)
        screenshot("today-tracking-stale")
    }

    func testHomeNearbyShortcutOpensTheSelectedStopBoard() {
        let app = launch("home")
        let nearby = app.buttons["home.nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 10))
        nearby.tap()
        let open = app.buttons["nearby.open.p3"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.navigationBars["彌敦道"].waitForExistence(timeout: 5))
        screenshot("home-nearby-stop-board")
    }

    func testSearchClearingAndNewQueryReplaceResults() {
        let app = launch("home")
        let shortcut = app.buttons["home.search"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        shortcut.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1A")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.route.")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertTrue(app.descendants(matching: .any)["search.landing"].waitForExistence(timeout: 5))
        let miss = "zz-no-route-zz"
        field.typeText(miss)
        XCTAssertTrue(app.descendants(matching: .any)["search.noResults"].waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: miss.count))
        field.typeText("1A")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 5))
        screenshot("home-search-replaced-query")
    }

    func testSelectedArrivalSurvivesWindowOrientationChange() {
        let app = launch("home")
        let open = app.buttons["boarding.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.navigationBars["1A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tracking.open"].exists)
        screenshot("arrival-after-orientation-change")
    }

    func testNativeToolbarCirclesAndActions() {
        let app = launch("home")
        assertCircular(app.buttons["app.region"])
        assertCircular(app.buttons["app.settings"])
        recordGeometry(app, ids: ["app.region", "app.settings"], name: "home-toolbar-geometry")
        screenshot("native-home-toolbar")
        app.buttons["app.settings"].tap()
        let settingsDone = app.buttons["settings.done"]
        XCTAssertTrue(settingsDone.waitForExistence(timeout: 5))
        settingsDone.tap()
        app.buttons["app.region"].tap()
        let regionDone = app.buttons["region.done"]
        XCTAssertTrue(regionDone.waitForExistence(timeout: 5))
        regionDone.tap()
        let open = app.buttons["boarding.open"]
        for _ in 0..<4 where !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let refresh = app.buttons["eta.refresh"]
        let favorite = app.buttons["eta.favorite"]
        assertCircular(refresh)
        assertCircular(favorite)
        assertSeparated(refresh, favorite)
        let previousLabel = favorite.label
        favorite.tap()
        XCTAssertNotEqual(favorite.label, previousLabel)
        favorite.tap()
        refresh.tap()
        recordGeometry(app, ids: ["eta.refresh", "eta.favorite"], name: "eta-toolbar-geometry")
        screenshot("native-eta-toolbar")
    }

    func testStopAndRouteToolbarCircles() {
        let app = launch("stop")
        assertCircular(app.buttons["stop.navigate"])
        assertCircular(app.buttons["stop.favorite"])
        assertSeparated(app.buttons["stop.navigate"], app.buttons["stop.favorite"])
        recordGeometry(app, ids: ["stop.navigate", "stop.favorite"], name: "stop-toolbar-geometry")
        screenshot("native-stop-toolbar")
        app.terminate()
        let route = launch("route")
        assertCircular(route.buttons["route.reverse"])
        assertCircular(route.buttons["route.favorite"])
        assertSeparated(route.buttons["route.reverse"], route.buttons["route.favorite"])
        recordGeometry(route, ids: ["route.reverse", "route.favorite"], name: "route-toolbar-geometry")
        screenshot("native-route-toolbar")
        route.buttons["route.reverse"].tap()
        XCTAssertTrue(route.buttons["route.stop.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(route.buttons["route.reverse"].isHittable)
    }

    func testCircularControlsRemainUsableWithReducedEffects() throws {
        let app = launch("home-tracking-eal", reduced: true)
        assertCircular(app.buttons["app.region"])
        assertCircular(app.buttons["app.settings"])
        let menu = app.buttons["home.tracking.menu"]
        for _ in 0..<4 where !menu.isHittable { app.swipeUp() }
        assertCircular(menu)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        recordGeometry(app, ids: ["home.tracking.menu"], name: "tracking-menu-geometry")
        screenshot("native-circles-reduced-effects")
    }

    private func assertCircular(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.waitForExistence(timeout: 10), file: file, line: line)
        guard button.exists else { return }
        XCTAssertTrue(button.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.width, 43.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height, 43.5, file: file, line: line)
        XCTAssertEqual(button.frame.width, button.frame.height, accuracy: 1, file: file, line: line)
    }

    private func assertSeparated(_ first: XCUIElement, _ second: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let gap = max(first.frame.minX, second.frame.minX) - min(first.frame.maxX, second.frame.maxX)
        XCTAssertGreaterThanOrEqual(gap, 4, "Each toolbar icon needs its own system platter", file: file, line: line)
    }

    private func recordGeometry(_ app: XCUIApplication, ids: [String], name: String) {
        let rows: [[String: Any]] = ids.map { id in
            let rect = app.buttons[id].frame
            return ["id": id, "x": Double(rect.minX), "y": Double(rect.minY),
                    "width": Double(rect.width), "height": Double(rect.height)]
        }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
