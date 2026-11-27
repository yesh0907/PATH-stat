import XCTest

/// Renders the shared Live Activity views via `-LiveActivityGallery <state>` (fixed sample
/// data, no ActivityKit, no network) and attaches one screenshot per state:
/// `live-activity-gallery-<state>`.
final class LiveActivityGalleryUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testLive() { check("live", expecting: "Updated") }
    @MainActor func testRolledOver() { check("rolledOver", expecting: "Updated") }
    @MainActor func testStale() { check("stale", expecting: "Updated") }
    @MainActor func testOffline() { check("offline", expecting: "Can't update") }
    @MainActor func testEnded() { check("ended", expecting: "Live Activity ended") }

    @MainActor
    private func check(_ state: String, expecting text: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-LiveActivityGallery", state]
        app.launch()
        XCTAssertTrue(element(app, "live-activity-gallery").waitForExistence(timeout: timeout))
        for part in ["lockscreen", "compact", "minimal", "expanded"] {
            XCTAssertTrue(element(app, "live-activity-\(part)").exists, "missing \(part)")
        }
        let lockScreen = element(app, "live-activity-lockscreen")
        let match = lockScreen.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let matchesSelf = lockScreen.label.contains(text)
        XCTAssertTrue(matchesSelf || match.waitForExistence(timeout: timeout), "Lock Screen should show “\(text)” for \(state)")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "live-activity-gallery-\(state)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
