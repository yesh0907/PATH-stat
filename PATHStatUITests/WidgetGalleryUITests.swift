import XCTest

/// Renders the shared widget views via `-WidgetGallery <state>` (fixed sample data, no network,
/// no widget host) and attaches one screenshot per state: `widget-gallery-<state>`.
final class WidgetGalleryUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testLive() { check("live", expecting: "Updated") }
    @MainActor func testStale() { check("stale", expecting: "Updated") }
    @MainActor func testOffline() { check("offline", expecting: "Can't update") }
    @MainActor func testUnavailable() { check("unavailable", expecting: "Can't reach PATH") }
    @MainActor func testNoTrains() { check("noTrains", expecting: "No trains predicted") }

    @MainActor
    private func check(_ state: String, expecting text: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-WidgetGallery", state]
        app.launch()
        XCTAssertTrue(element(app, "widget-gallery").waitForExistence(timeout: timeout))
        for family in ["systemSmall", "systemMedium", "accessoryRectangular", "accessoryCircular", "accessoryInline"] {
            XCTAssertTrue(element(app, "widget-\(family)").exists, "missing \(family)")
        }
        let small = element(app, "widget-systemSmall")
        let match = small.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: timeout), "systemSmall should show “\(text)” for \(state)")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "widget-gallery-\(state)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
}
