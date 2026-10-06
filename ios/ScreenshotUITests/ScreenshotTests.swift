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
        // iPad and iPhone Duo show the selection beside the list; select a
        // row so the detail is not an empty placeholder.
        let isWide = app.staticTexts["Nothing selected"].exists
        if isWide { select("Send design review notes", in: app) }
        capture("01-available")

        let upcoming = app.buttons["Upcoming"].firstMatch
        upcoming.tap()
        XCTAssertTrue(app.staticTexts["Tomorrow"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Book annual check-up"].exists)
        if isWide { select("Book annual check-up", in: app) }
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

    private func select(_ title: String, in app: XCUIApplication) {
        app.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.textFields["What needs doing?"].firstMatch.waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        // iPhone Duo reports its small outer display as main; capture the
        // largest display, which is the one showing the app.
        let screenshot = XCUIScreen.screens.map { $0.screenshot() }
            .max { $0.image.size.width * $0.image.size.height < $1.image.size.width * $1.image.size.height }!
        // The Duo's inner display is stored rotated with an orientation
        // flag; redraw upright so the PNG's pixels match what is shown.
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .standard
        let png = UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in image.draw(at: .zero) }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
