import XCTest

/// Shared helpers for the scenario-mode UI test classes. Holds no tests itself, so it is not
/// run on its own; the concrete classes are split so parallel testing can balance them.
class PATHStatUITestCase: XCTestCase {
    let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    enum ScrollDirection { case up, down }

    /// Swipes (at most a few times) until `target` is hittable; returns immediately if it already is.
    @MainActor
    func scroll(_ app: XCUIApplication, until target: XCUIElement, direction: ScrollDirection) {
        for _ in 0..<6 {
            if target.isHittable { return }
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(target.isHittable, "\(target) is not hittable")
    }

    @MainActor
    func wait(for target: XCUIElement, _ format: String) {
        expectation(for: NSPredicate(format: format), evaluatedWith: target)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    func launch(scenario: String, location: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", scenario]
        if let location { app.launchArguments += ["-UITestLocation", location] }
        app.launch()
        return app
    }

    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
