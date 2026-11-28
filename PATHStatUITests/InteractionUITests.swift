import XCTest

/// Station picker, favorites and Live Activity interactions in scenario mode.
final class InteractionUITests: PATHStatUITestCase {
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
}
