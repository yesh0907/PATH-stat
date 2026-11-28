import XCTest

/// Drives the app in its deterministic `-UITestScenario` modes (stub feed, fixed location,
/// throwaway favourites) and attaches a screenshot per test.
final class PATHStatUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Scenarios

    @MainActor
    func testLoading() {
        let app = launch(scenario: "loading")
        XCTAssertTrue(element(app, "state-loading").waitForExistence(timeout: timeout))
        XCTAssertFalse(element(app, "next-train").exists)
        attachScreenshot(app, "loading")
    }

    @MainActor
    func testTrains() {
        let app = launch(scenario: "trains")
        let next = element(app, "next-train")
        XCTAssertTrue(next.waitForExistence(timeout: timeout))
        XCTAssertTrue(next.label.hasPrefix("Next train to 33rd Street"), next.label)
        XCTAssertTrue(next.label.contains(" line, arriving "), next.label)
        XCTAssertTrue(element(app, "following-train").exists)
        XCTAssertTrue(element(app, "later-train-0").exists)
        XCTAssertTrue(element(app, "later-train-1").exists)
        XCTAssertTrue(element(app, "freshness-footer").label.hasPrefix("Updated"))
        XCTAssertTrue(element(app, "station-header").label.contains("Grove Street"))
        XCTAssertTrue(element(app, "destination-33S").isSelected)
        XCTAssertFalse(element(app, "destination-WTC").isSelected)
        XCTAssertTrue(element(app, "favorite-toggle").exists)
        XCTAssertTrue(element(app, "favorite-GRV-33S").exists)
        let liveActivity = element(app, "live-activity-button")
        XCTAssertTrue(liveActivity.exists)
        XCTAssertTrue(liveActivity.isEnabled)
        XCTAssertFalse(element(app, "live-activity-status").exists)
        attachScreenshot(app, "trains")
    }

    @MainActor
    func testNoTrains() {
        let app = launch(scenario: "noTrains")
        let empty = element(app, "state-no-trains")
        XCTAssertTrue(empty.waitForExistence(timeout: timeout))
        XCTAssertTrue(empty.label.contains("No trains to 33rd St right now"), empty.label)
        XCTAssertTrue(element(app, "freshness-footer").label.hasPrefix("Updated"))
        XCTAssertFalse(element(app, "next-train").exists)
        attachScreenshot(app, "no-trains")
    }

    @MainActor
    func testOffline() {
        let app = launch(scenario: "offline")
        XCTAssertTrue(element(app, "state-offline").waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Can't reach PATH"].exists)
        XCTAssertTrue(element(app, "retry-button").exists)
        attachScreenshot(app, "offline")
    }

    @MainActor
    func testLocationDenied() {
        let app = launch(scenario: "locationDenied")
        let banner = element(app, "location-denied-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["Location is off — showing Grove St"].exists)
        XCTAssertTrue(element(app, "choose-station-button").exists)
        XCTAssertTrue(element(app, "open-settings-button").exists)
        let header = element(app, "station-header")
        XCTAssertTrue(header.label.contains("Grove Street"), header.label)
        XCTAssertTrue(header.label.contains("home station"), header.label)
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        attachScreenshot(app, "location-denied")
    }

    @MainActor
    func testOfflineWithDataShowsBanner() {
        let app = launch(scenario: "offlineWithData")
        let banner = element(app, "offline-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: timeout))
        XCTAssertTrue(banner.label.hasPrefix("Can't update — showing data from"), banner.label)
        XCTAssertTrue(element(app, "next-train").exists)
        attachScreenshot(app, "offline-with-data")
    }

    // MARK: Smart default by location

    @MainActor
    func testNearGroveStreetDefaultsToThirtyThird() {
        let app = launch(scenario: "trains", location: "40.7190,-74.0430")
        let header = element(app, "station-header")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(header.label.contains("Grove Street"), header.label)
        XCTAssertTrue(header.label.contains("nearest"), header.label)
        let chip = element(app, "destination-33S")
        XCTAssertEqual(chip.label, "Destination 33rd St")
        XCTAssertTrue(chip.isSelected)
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        attachScreenshot(app, "near-grove-street")
    }

    @MainActor
    func testNearTwentyThirdDefaultsToGoingHome() {
        let app = launch(scenario: "trains", location: "40.7432,-73.9925")
        let header = element(app, "station-header")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(header.label.contains("23rd Street"), header.label)
        let chip = element(app, "destination-GRV")
        XCTAssertTrue(chip.exists)
        XCTAssertEqual(chip.label, "Destination Grove St, home")
        XCTAssertTrue(chip.isSelected)
        XCTAssertEqual(element(app, "trip-title").label, "Going home")
        let next = element(app, "next-train")
        XCTAssertTrue(next.waitForExistence(timeout: timeout))
        XCTAssertTrue(next.label.hasPrefix("Next train to Journal Square"), next.label)
        attachScreenshot(app, "near-23rd-street")
    }

    @MainActor
    func testNearHobokenUsesHoboken() {
        let app = launch(scenario: "trains", location: "40.7370,-74.0300")
        let header = element(app, "station-header")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(header.label.contains("Hoboken"), header.label)
        // The smart trip heads home: Hoboken → Grove St.
        XCTAssertTrue(element(app, "destination-GRV").isSelected)
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        attachScreenshot(app, "near-hoboken")
    }

    @MainActor
    func testOneTapHomeFromTwentyThird() {
        let app = launch(scenario: "trains", location: "40.7432,-73.9925")
        XCTAssertTrue(element(app, "station-header").waitForExistence(timeout: timeout))
        XCTAssertEqual(element(app, "trip-title").label, "Going home")

        element(app, "destination-33S").tap()
        wait(for: element(app, "destination-33S"), "isSelected == true")
        XCTAssertNotEqual(element(app, "trip-title").label, "Going home")

        element(app, "destination-GRV").tap()
        wait(for: element(app, "destination-GRV"), "isSelected == true")
        XCTAssertEqual(element(app, "trip-title").label, "Going home")
        attachScreenshot(app, "one-tap-home")
    }

    // MARK: Interaction

    @MainActor
    func testStationPickerChangesOrigin() {
        let app = launch(scenario: "trains")
        let header = element(app, "station-header")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        header.tap()
        let hoboken = element(app, "station-HOB")
        XCTAssertTrue(hoboken.waitForExistence(timeout: timeout))
        attachScreenshot(app, "station-picker")
        hoboken.tap()
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        let predicate = NSPredicate(format: "label CONTAINS 'Hoboken'")
        expectation(for: predicate, evaluatedWith: header)
        waitForExpectations(timeout: timeout)
        // 33rd St is still reachable from Hoboken (Hoboken–33rd St), so the destination is kept.
        XCTAssertTrue(element(app, "destination-33S").isSelected)
    }

    @MainActor
    func testFavoriteSwitchesTrip() {
        let app = launch(scenario: "trains", location: "40.7190,-74.0430")
        let header = element(app, "station-header")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "destination-33S").isSelected)

        let favorite = element(app, "favorite-GRV-WTC")
        XCTAssertTrue(favorite.waitForExistence(timeout: timeout))
        scroll(app, until: favorite, direction: .up)
        favorite.tap()
        wait(for: element(app, "destination-WTC"), "isSelected == true")
        XCTAssertFalse(element(app, "destination-33S").isSelected)
        XCTAssertTrue(favorite.isSelected)
        attachScreenshot(app, "favorite-switch")

        scroll(app, until: header, direction: .down)
        header.tap()
        let hoboken = element(app, "station-HOB")
        XCTAssertTrue(hoboken.waitForExistence(timeout: timeout))
        scroll(app, until: hoboken, direction: .up)
        hoboken.tap()
        wait(for: header, "label CONTAINS 'Hoboken'")
    }

    // MARK: Live Activity (in-memory stub backend in scenario mode)

    @MainActor
    func testStartAndStopLiveActivity() {
        let app = launch(scenario: "trains")
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        let button = element(app, "live-activity-button")
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        scroll(app, until: button, direction: .up)
        button.tap()

        let status = element(app, "live-activity-status")
        XCTAssertTrue(status.waitForExistence(timeout: timeout))
        XCTAssertTrue(status.label.contains("On Lock Screen"), status.label)
        XCTAssertFalse(element(app, "live-activity-button").exists)
        let stop = element(app, "live-activity-stop")
        XCTAssertTrue(stop.exists)
        scroll(app, until: stop, direction: .up)
        attachScreenshot(app, "live-activity-started")

        stop.tap()
        wait(for: status, "exists == false")
        XCTAssertTrue(element(app, "live-activity-button").waitForExistence(timeout: timeout))
        XCTAssertFalse(element(app, "live-activity-stop").exists)
        attachScreenshot(app, "live-activity-stopped")
    }

    // MARK: Layout stability

    @MainActor
    func testSwitchingDirectionDoesNotShiftLayout() throws {
        let app = launch(scenario: "trains", location: "40.7190,-74.0430")
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "destination-33S").isSelected)
        let tracked = [
            "direction-control", "destination-33S", "destination-WTC", "more-destinations",
            "next-train", "following-train", "later-trains", "favorites-section",
        ]

        let on33rd = try frames(app, tracked)
        attachScreenshot(app, "direction-33S")

        element(app, "destination-WTC").tap()
        wait(for: element(app, "destination-WTC"), "isSelected == true")
        let onWTC = try frames(app, tracked)
        try assertFramesEqual(on33rd, onWTC, tracked: tracked, label: "switching to WTC")
        attachScreenshot(app, "direction-WTC")

        element(app, "destination-33S").tap()
        wait(for: element(app, "destination-33S"), "isSelected == true")
        let backOn33rd = try frames(app, tracked)
        try assertFramesEqual(onWTC, backOn33rd, tracked: tracked, label: "switching back to 33rd St")
    }

    @MainActor
    func testSwitchingDirectionWithLiveActivityDoesNotShiftLayout() throws {
        let app = launch(scenario: "trains", location: "40.7432,-73.9925")
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "destination-GRV").isSelected)
        XCTAssertTrue(element(app, "destination-33S").exists)

        let follow = element(app, "live-activity-button")
        XCTAssertTrue(follow.waitForExistence(timeout: timeout))
        scroll(app, until: follow, direction: .up)
        follow.tap()
        XCTAssertTrue(element(app, "live-activity-status").waitForExistence(timeout: timeout))

        let tracked = [
            "direction-control", "destination-GRV", "destination-33S", "more-destinations",
            "next-train", "following-train", "later-trains", "favorites-section", "live-activity-status",
        ]
        let onGrove = try frames(app, tracked)

        element(app, "destination-33S").tap()
        wait(for: element(app, "destination-33S"), "isSelected == true")
        let switchButton = element(app, "live-activity-button")
        let stopButton = element(app, "live-activity-stop")
        XCTAssertTrue(switchButton.waitForExistence(timeout: timeout))
        XCTAssertTrue(stopButton.exists)
        XCTAssertEqual(switchButton.frame.midY, stopButton.frame.midY, accuracy: 1, "Switch and Stop are not on one row")
        let on33rd = try frames(app, tracked)
        // The status text changes here, so its width does too; its position and height don't.
        let layoutTracked = tracked.filter { $0 != "live-activity-status" }
        try assertFramesEqual(onGrove, on33rd, tracked: layoutTracked, label: "switching direction with a Live Activity for another trip")
        let statusBefore = try XCTUnwrap(onGrove["live-activity-status"])
        let statusAfter = try XCTUnwrap(on33rd["live-activity-status"])
        XCTAssertEqual(statusBefore.minX, statusAfter.minX, accuracy: 0.5, "live-activity-status x moved")
        XCTAssertEqual(statusBefore.minY, statusAfter.minY, accuracy: 0.5, "live-activity-status y moved")
        XCTAssertEqual(statusBefore.height, statusAfter.height, accuracy: 0.5, "live-activity-status height changed")
        attachScreenshot(app, "live-activity-other-trip")

        element(app, "destination-GRV").tap()
        wait(for: element(app, "destination-GRV"), "isSelected == true")
        let backOnGrove = try frames(app, tracked)
        try assertFramesEqual(onGrove, backOnGrove, tracked: tracked, label: "switching back with a Live Activity")
    }

    @MainActor
    func testSingleTrainShowsPlaceholder() throws {
        let app = launch(scenario: "singleTrain", location: "40.7190,-74.0430")
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "destination-33S").isSelected)
        let nextOn33rd = element(app, "next-train").frame
        let favoritesOn33rd = element(app, "favorites-section").frame

        element(app, "destination-WTC").tap()
        wait(for: element(app, "destination-WTC"), "isSelected == true")

        // Grove St → WTC is only the Newark–WTC line: exactly one train in the feed.
        XCTAssertTrue(element(app, "next-train").exists)
        XCTAssertTrue(element(app, "following-train-placeholder").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "later-trains-placeholder").exists)
        XCTAssertFalse(element(app, "following-train").exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'later-train-'")).count, 0)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "following-train").count, 0)
        XCTAssertEqual(element(app, "next-train").frame.minY, nextOn33rd.minY, accuracy: 0.5)
        XCTAssertEqual(element(app, "next-train").frame.height, nextOn33rd.height, accuracy: 0.5)
        XCTAssertEqual(element(app, "favorites-section").frame.minY, favoritesOn33rd.minY, accuracy: 0.5)
        attachScreenshot(app, "single-train")
    }

    // MARK: Helpers

    @MainActor
    private func frames(_ app: XCUIApplication, _ tracked: [String]) throws -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        for id in tracked {
            let target = element(app, id)
            XCTAssertTrue(target.exists, id)
            result[id] = target.frame
        }
        return result
    }

    @MainActor
    private func assertFramesEqual(_ a: [String: CGRect], _ b: [String: CGRect], tracked: [String], label: String) throws {
        for id in tracked {
            let first = try XCTUnwrap(a[id], id)
            let second = try XCTUnwrap(b[id], id)
            XCTAssertEqual(first.minX, second.minX, accuracy: 0.5, "\(id) x moved when \(label)")
            XCTAssertEqual(first.minY, second.minY, accuracy: 0.5, "\(id) y moved when \(label)")
            XCTAssertEqual(first.width, second.width, accuracy: 0.5, "\(id) width changed when \(label)")
            XCTAssertEqual(first.height, second.height, accuracy: 0.5, "\(id) height changed when \(label)")
        }
    }

    private enum ScrollDirection { case up, down }

    /// Swipes (at most a few times) until `target` is hittable.
    @MainActor
    private func scroll(_ app: XCUIApplication, until target: XCUIElement, direction: ScrollDirection) {
        for _ in 0..<6 where !target.isHittable {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(target.isHittable, "\(target) is not hittable")
    }

    @MainActor
    private func wait(for target: XCUIElement, _ format: String) {
        expectation(for: NSPredicate(format: format), evaluatedWith: target)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    private func launch(scenario: String, location: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", scenario]
        if let location { app.launchArguments += ["-UITestLocation", location] }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
