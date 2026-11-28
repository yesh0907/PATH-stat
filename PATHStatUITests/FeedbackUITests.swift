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
        // The main screen has one feedback entry point.
        XCTAssertTrue(element(app, "next-train").waitForExistence(timeout: timeout))
        XCTAssertTrue(button(app, "send-feedback-button").exists)
        XCTAssertFalse(element(app, "send-feedback-footer").exists)
        XCTAssertFalse(element(app, "feedback-settings-button").exists)
        openViaButton(app)

        XCTAssertTrue(element(app, "feedback-screenshot").exists)
        let idea = button(app, "feedback-category-idea")
        XCTAssertTrue(element(app, "feedback-category-bug").isSelected)
        XCTAssertFalse(idea.isSelected)
        let send = button(app, "feedback-send")
        XCTAssertTrue(send.isEnabled, "a screenshot alone can be sent")

        // Choose the category before the multiline note can shift the chips.
        idea.tap()
        wait(for: idea, "isSelected == true")
        XCTAssertFalse(element(app, "feedback-category-bug").isSelected)
        typeNote(app, "Froze at 2:13\nstuck")
        attachScreenshot(app, "feedback-compose")

        send.tap()
        let sent = element(app, "feedback-sent")
        XCTAssertTrue(sent.waitForExistence(timeout: timeout))
        XCTAssertEqual(sent.label, "Sent as #42")
        XCTAssertTrue(element(app, "feedback-issue-link").exists)
        attachScreenshot(app, "feedback-sent")

        button(app, "feedback-done").tap()
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
        // Regression: a shake during the dismissal animation must not wedge presentation.
        shake(app)
        let sheet = element(app, "feedback-sheet")
        if !sheet.waitForNonExistence(timeout: 2) {
            // The shake can re-open the sheet if dismissal completed before delivery.
            element(app, "feedback-cancel").tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: timeout))
        }

        // A shake after the sheet is fully gone opens it again.
        shake(app)
        XCTAssertTrue(element(app, "feedback-sheet").waitForExistence(timeout: timeout))
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
        typeNote(app, "Dark icon")
        button(app, "feedback-category-design-nit").tap()
        button(app, "feedback-send").tap()

        let queued = element(app, "feedback-queued")
        XCTAssertTrue(queued.waitForExistence(timeout: timeout))
        let reason = element(app, "feedback-queued-reason").label
        XCTAssertTrue(reason.contains("Feedback settings"), reason)
        XCTAssertTrue(button(app, "feedback-queued-settings").exists)
        XCTAssertTrue(element(app, "feedback-share").exists)
        attachScreenshot(app, "feedback-queued-no-token")

        button(app, "feedback-queued-settings").tap()
        XCTAssertTrue(element(app, "feedback-settings").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-token-field").waitForExistence(timeout: timeout))
        button(app, "feedback-settings-done").tap()
        wait(for: element(app, "feedback-settings"), "exists == false")
        XCTAssertTrue(element(app, "feedback-queued").exists)
        button(app, "feedback-done").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")

        let pending = button(app, "feedback-pending")
        XCTAssertTrue(pending.waitForExistence(timeout: timeout))
        XCTAssertTrue(pending.label.contains("1 report waiting"), pending.label)
        pending.tap()
        XCTAssertTrue(element(app, "feedback-settings").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-token-field").exists)
        XCTAssertTrue(element(app, "feedback-retry").exists)
        XCTAssertTrue(app.staticTexts["Dark icon"].exists)
        attachScreenshot(app, "feedback-settings-waiting")
    }

    @MainActor
    func testOfflineQueued() {
        let app = launch(feedback: "offline")
        openViaButton(app)
        typeNote(app, "Late trains")
        button(app, "feedback-send").tap()

        XCTAssertTrue(element(app, "feedback-queued").waitForExistence(timeout: timeout))
        let reason = element(app, "feedback-queued-reason")
        XCTAssertTrue(reason.label.contains("Can't reach GitHub"), reason.label)
        XCTAssertTrue(element(app, "feedback-share").exists)
        attachScreenshot(app, "feedback-queued-offline")
        button(app, "feedback-done").tap()
        wait(for: element(app, "feedback-sheet"), "exists == false")
        XCTAssertTrue(button(app, "feedback-pending").waitForExistence(timeout: timeout))
    }

    @MainActor
    func testRemoveScreenshot() {
        let app = launch(feedback: "sent")
        openViaButton(app)
        let screenshot = element(app, "feedback-screenshot")
        let toggle = element(app, "feedback-remove-screenshot")
        let send = button(app, "feedback-send")
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
        typeNote(app, "Header bug")
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(element(app, "feedback-sent").waitForExistence(timeout: timeout))
    }

    @MainActor
    func testSettingsReachableFromSheet() {
        let app = launch(feedback: "sent")
        openViaButton(app)
        let settingsButton = element(app, "feedback-settings-button")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: timeout))
        settingsButton.tap()
        XCTAssertTrue(element(app, "feedback-settings").waitForExistence(timeout: timeout))
        XCTAssertTrue(element(app, "feedback-token-field").exists)
        attachScreenshot(app, "feedback-settings-from-sheet")
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
        let feedbackButton = button(app, "send-feedback-button")
        XCTAssertTrue(feedbackButton.waitForExistence(timeout: timeout))
        feedbackButton.tap()
        XCTAssertTrue(element(app, "feedback-sheet").waitForExistence(timeout: timeout))
        XCTAssertTrue(noteField(app).waitForExistence(timeout: timeout))
    }

    @MainActor
    private func shake(_ app: XCUIApplication) {
        let button = element(app, "debug-simulate-shake")
        XCTAssertTrue(button.waitForExistence(timeout: timeout))
        button.tap()
    }

    @MainActor
    private func typeNote(_ app: XCUIApplication, _ text: String) {
        let note = noteField(app)
        note.tap()
        note.typeText(text)
    }

    @MainActor
    private func noteField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["feedback-note"].firstMatch
    }

    @MainActor
    private func button(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.buttons[identifier].firstMatch
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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
