import XCTest

/// Product-only App Store captures, using the same sample catalog as Settings.
/// The fixture is compiled only when TODO_SCREENSHOTS is defined and requires
/// the explicit --screenshot-demo launch argument.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureAppScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["--screenshot-demo"]
        app.launch()

        // iOS 27 renders these as a bottom tab bar on iPhone and a top
        // segmented control on iPad; query by accessible title on both.
        let available = app.buttons["Available"].firstMatch
        XCTAssertTrue(available.waitForExistence(timeout: 30), "Screenshot fixture did not open the task list")
        XCTAssertTrue(app.staticTexts["Buy fresh pasta"].waitForExistence(timeout: 10))
        capture("01-available")

        let upcoming = app.buttons["Upcoming"].firstMatch
        upcoming.tap()
        XCTAssertTrue(app.staticTexts["Tomorrow"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Book annual check-up"].exists)
        capture("02-upcoming")

        available.tap()
        // Exposed as a toggle (switch), not a plain button.
        app.switches["Expand projects"].firstMatch.tap()
        let shopping = app.staticTexts["Weekend shopping"].firstMatch
        XCTAssertTrue(shopping.waitForExistence(timeout: 10))
        shopping.tap()
        XCTAssertTrue(app.staticTexts["Get parmesan"].waitForExistence(timeout: 10))
        capture("03-project")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
