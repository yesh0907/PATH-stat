import XCTest

/// Best-effort: adds the real widget (small + medium) to the Simulator's Home Screen through
/// Springboard and screenshots it with live feed data. Opt-in, because it uses the network and
/// edits the Home Screen:
///
///     TEST_RUNNER_PATH_WIDGET_SCREENSHOTS=1 xcodebuild test ... \
///       -only-testing:PATHStatUITests/HomeScreenWidgetUITests
///
/// Springboard's UI differs between iOS versions; every step looks for several known labels and
/// attaches a screenshot of where it got stuck.
final class HomeScreenWidgetUITests: XCTestCase {
    @MainActor private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PATH_WIDGET_SCREENSHOTS"] == "1",
            "Set TEST_RUNNER_PATH_WIDGET_SCREENSHOTS=1 to add the widget to the Home Screen and screenshot it."
        )
        continueAfterFailure = false
    }

    @MainActor
    func testAddWidgetsToHomeScreen() throws {
        // Launch the live app once so the widget extension is registered, then go home.
        let app = XCUIApplication()
        app.launch()
        sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(1)
        // An empty page makes the long press land on the wallpaper, not an icon.
        for _ in 0..<3 { springboard.swipeLeft(); sleep(1) }

        try addWidget(sizeIndex: 0)
        try addWidget(sizeIndex: 1)
        exitEditMode()

        // Let the widget fetch the live feed and render.
        sleep(10)
        attach("home-screen-widgets")
    }

    // MARK: Steps

    @MainActor
    private func addWidget(sizeIndex: Int) throws {
        enterEditMode()
        try openWidgetGallery()

        let search = springboard.searchFields.firstMatch
        try require(search.waitForExistence(timeout: 5), "widget gallery search field")
        search.tap()
        search.typeText("PATH Stat")
        sleep(2)
        let result = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "PATH Stat")).allElementsBoundByIndex
            .first { $0.isHittable && $0.elementType != .searchField }
        try require(result != nil, "“PATH Stat” in widget search results")
        result!.tap()
        sleep(2)

        for _ in 0..<sizeIndex {
            springboard.swipeLeft()
            sleep(1)
        }
        let add = springboard.buttons["Add Widget"].firstMatch
        try require(add.waitForExistence(timeout: 5), "“Add Widget” button")
        add.tap()
        sleep(2)
    }

    @MainActor
    private func enterEditMode() {
        if springboard.buttons["Done"].exists { return }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(forDuration: 1.5)
        sleep(1)
        // A long press on an icon shows a context menu instead.
        let editHome = springboard.buttons["Edit Home Screen"].firstMatch
        if editHome.exists { editHome.tap(); sleep(1) }
    }

    @MainActor
    private func openWidgetGallery() throws {
        // iOS 17: a "+" / "Add Widget" button; iOS 18+: "Edit" → "Add Widget".
        for label in ["Add Widget", "Add", "+"] {
            let button = springboard.buttons[label].firstMatch
            if button.exists, button.isHittable {
                button.tap()
                sleep(2)
                return
            }
        }
        let edit = springboard.buttons["Edit"].firstMatch
        try require(edit.waitForExistence(timeout: 3), "Home Screen “Edit” / “+” button")
        edit.tap()
        sleep(1)
        let addWidget = springboard.buttons["Add Widget"].firstMatch
        try require(addWidget.waitForExistence(timeout: 3), "“Add Widget” in the Edit menu")
        addWidget.tap()
        sleep(2)
    }

    @MainActor
    private func exitEditMode() {
        let done = springboard.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { XCUIDevice.shared.press(.home) }
        sleep(1)
    }

    // MARK: Helpers

    @MainActor
    private func require(_ condition: Bool, _ what: String) throws {
        guard condition else {
            attach("home-screen-widgets-stuck")
            XCTFail("Springboard automation couldn't find \(what)")
            throw XCTSkip("Stopped: \(what) not found")
        }
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
