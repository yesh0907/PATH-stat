import XCTest

/// Drives the app in its deterministic `-UITestScenario` modes (stub feed, fixed location,
/// throwaway favourites) and attaches a screenshot per test. Interaction and layout tests live
/// in `InteractionUITests` / `LayoutUITests` (same base class) so parallel testing can balance them.
final class PATHStatUITests: PATHStatUITestCase {
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
        XCTAssertFalse(element(app, "next-train-scheduled").exists)
        attachScreenshot(app, "no-trains")
    }

    @MainActor
    func testScheduleFallbackShowsScheduledTrainWithUnknownRealtimeStatus() {
        let app = launch(scenario: "scheduleFallback")
        let scheduled = element(app, "next-train-scheduled")
        XCTAssertTrue(scheduled.waitForExistence(timeout: timeout))
        XCTAssertTrue(scheduled.label.hasPrefix("Scheduled train to World Trade Center"), scheduled.label)
        XCTAssertTrue(scheduled.label.contains("No real-time status reported"), scheduled.label)
        XCTAssertTrue(element(app, "destination-WTC").isSelected)
        XCTAssertFalse(element(app, "next-train").exists)
        XCTAssertFalse(element(app, "state-no-trains").exists)
        attachScreenshot(app, "schedule-fallback")
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

        // Switch away from and back to home with one tap each.
        element(app, "destination-33S").tap()
        wait(for: element(app, "destination-33S"), "isSelected == true")
        XCTAssertNotEqual(element(app, "trip-title").label, "Going home")

        element(app, "destination-GRV").tap()
        wait(for: element(app, "destination-GRV"), "isSelected == true")
        XCTAssertEqual(element(app, "trip-title").label, "Going home")
        attachScreenshot(app, "one-tap-home")
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
}
