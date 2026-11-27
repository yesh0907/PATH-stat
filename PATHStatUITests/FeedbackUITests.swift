import XCTest

/// In-app feedback in scenario mode: stub GitHub service (`-UITestFeedback <sent|offline|noToken>`),
/// in-memory token, throwaway queue. Never touches the network. Shakes come from the
/// near-invisible `debug-simulate-shake` button, which posts the same notification as a real shake.
final class FeedbackUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSendViaButton() {
        let app = launch(feedback: "sent")
        openViaButton(app)

        XCTAssertTrue(element(app, "feedback-screenshot").exists)
        XCTAssertTrue(element(app, "feedback-category-bug").isSelected)
        XCTAssertFalse(element(app, "feedback-category-idea").isSelected)
        let send = element(app, "feedback-send")
        XCTAssertTrue(send.isEnabled, "a screenshot alone can be sent")

        typeNote(app, "Countdown froze at Grove St\nIt stuck at 2:13.")
        element(app, "feedback-category-idea").tap()
        wait(for: element(app, "feedback-category-idea"), "isSelected == true")
        XCTAssertFalse(element(app, "feedback-category-bug").isSelected)
        attachScreenshot(app, "feedback-compose")

        send.tap()
        let sent = element(app, "feedback-sent")
        XCTAssertTrue(sent.waitForExistence(timeout: timeout))
        XCTAssertEqual(sent.label, "Sent as #42")
        XCTAssertTrue(element(app, "feedback-issue-link").exists)
        attachScreenshot(app, "feedback-sent")

        element(app, "feedback-done").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")
        XCTAssertFalse(element(app, "feedback-pending").exists)
    }

    @MainActor
    func testOpenViaShake() {
        let app = launch(feedback: "sent")
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))

        shake(app)
        XCTAssertTrue(element(app, "feedback-sheet").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-screenshot").exists)
        // A second shake while the sheet is up is ignored.
        shake(app)
        XCTAssertTrue(element(app, "feedback-note").exists)
        element(app, "feedback-cancel").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")

        // Over the station picker: the sheet presents on top and the picker stays underneath.
        element(app, "station-header").tap()
        let hoboken = element(app, "station-HOB")
        XCTAssertTrue(hoboken.waitForExistence(timeout: timeout))
        shake(app)
        XCTAssertTrue(element(app, "feedback-sheet").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-screenshot").exists)
        attachScreenshot(app, "feedback-over-station-picker")
        element(app, "feedback-cancel").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")
        XCTAssertTrue(hoboken.waitForExistence(timeout: timeout))
    }

    @MainActor
    func testQueuedWithoutToken() {
        let app = launch(feedback: "noToken")
        openViaButton(app)
        typeNote(app, "Add a dark mode icon")
        element(app, "feedback-category-design-nit").tap()
        element(app, "feedback-send").tap()

        let queued = element(app, "feedback-queued")
        XCTAssertTrue(queued.waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-queued-reason").label.contains("No GitHub token"), element(app, "feedback-queued-reason").label)
        XCTAssertTrue(element(app, "feedback-share").exists)
        attachScreenshot(app, "feedback-queued-no-token")
        element(app, "feedback-done").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")

        let pending = element(app, "feedback-pending")
        XCTAssertTrue(pending.waitForExistence(timeout: timeout))
        XCTAssertTrue(pending.label.contains("1 report waiting"), pending.label)
        pending.tap()
        XCTAssertTrue(element(app, "feedback-settings").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-token-field").exists)
        XCTAssertTrue(element(app, "feedback-retry").exists)
        XCTAssertTrue(app.staticTexts["Add a dark mode icon"].exists)
        attachScreenshot(app, "feedback-settings-waiting")
    }

    @MainActor
    func testOfflineQueued() {
        let app = launch(feedback: "offline")
        openViaButton(app)
        typeNote(app, "Trains missing after 1am")
        element(app, "feedback-send").tap()

        XCTAssertTrue(element(app, "feedback-queued").waitForExistence(timeout: timeout))
        let reason = element(app, "feedback-queued-reason")
        XCTAssertTrue(reason.label.contains("Can't reach GitHub"), reason.label)
        XCTAssertTrue(element(app, "feedback-share").exists)
        attachScreenshot(app, "feedback-queued-offline")
        element(app, "feedback-done").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")
        XCTAssertTrue(element(app, "feedback-pending").waitForExistence(timeout: timeout))
    }

    @MainActor
    func testRemoveScreenshot() {
        let app = launch(feedback: "sent")
        openViaButton(app)
        let screenshot = element(app, "feedback-screenshot")
        let toggle = element(app, "feedback-remove-screenshot")
        let send = element(app, "feedback-send")
        XCTAssertTrue(screenshot.exists)
        XCTAssertTrue(send.isEnabled, "a screenshot alone can be sent")

        toggle.tap()
        wait(for: screenshot, "exists == false")
        XCTAssertFalse(send.isEnabled, "nothing to send without a note or screenshot")
        attachScreenshot(app, "feedback-screenshot-removed")

        toggle.tap()   // "Add screenshot back"
        XCTAssertTrue(screenshot.waitForExistence(timeout: timeout))
        XCTAssertTrue(send.isEnabled)

        toggle.tap()
        wait(for: screenshot, "exists == false")
        typeNote(app, "Header overlaps the clock")
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(element(app, "feedback-sent").waitForExistence(timeout: timeout))
    }

    // MARK: Helpers

    @MainActor
    private func launch(feedback: String, scenario: String = "trains") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestScenario", scenario, "-UITestFeedback", feedback]
        app.launch()
        return app
    }

    @MainActor
    private func openViaButton(_ app: XCUIApplication) {
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        let button = element(app, "send-feedback-button")
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.tap()
        XCTAssertTrue(element(app, "feedback-sheet").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-note").waitForExistence(timeout: timeout))
    }

    @MainActor
    private func shake(_ app: XCUIApplication) {
        let button = element(app, "debug-simulate-shake")
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.tap()
    }

    @MainActor
    private func typeNote(_ app: XCUIApplication, _ text: String) {
        let note = element(app, "feedback-note")
        XCTAssertTrue(note.waitForExistence(timeout: timeout))
        note.tap()
        note.typeText(text)
    }

    @MainActor
    private func wait(for target: XCUIElement, _ format: String) {
        expectation(for: NSPredicate(format: format), evaluatedWith: target)
        waitForExpectations(timeout: timeout)
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
