import XCTest

/// Layout stability: switching direction must not move anything on the board.
final class LayoutUITests: PATHStatUITestCase {
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

    /// One accessibility lookup per element: `.frame` fails the test if nothing matches, and an
    /// empty frame means the element is not laid out.
    @MainActor
    private func frames(_ app: XCUIApplication, _ tracked: [String]) throws -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        for id in tracked {
            let frame = element(app, id).frame
            XCTAssertFalse(frame.isEmpty, id)
            result[id] = frame
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
}
