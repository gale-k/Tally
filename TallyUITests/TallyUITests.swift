import XCTest

/// UI smoke coverage grows with the app; no test writes to the user's Health store.
final class TallyUITests: XCTestCase {
    @MainActor
    func testAppLaunchesWithFourTabs() {
        let app = XCUIApplication()
        app.launch()
        for title in ["Today", "Drinks", "History", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[title].exists)
        }
    }
}
