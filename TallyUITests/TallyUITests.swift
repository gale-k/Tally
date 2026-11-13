import XCTest

/// Every UI test injects an in-memory library and fake Health store. Real health data is never read or written.
@MainActor
final class TallyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppLaunchesWithFourTabs() {
        let app = launch()
        for title in ["Today", "Drinks", "History", "Settings"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        XCTAssertTrue(app.buttons["chooseHealthAccess"].exists)
    }

    func testCreateTemplateWithUnknownNutritionAndSearch() {
        let app = launch()
        app.tabBars.buttons["Drinks"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Mystery Coffee")
        capture("Editor-Name-Keyboard", app)
        app.buttons["saveDrink"].tap()
        let drink = app.buttons["drink.Mystery Coffee"]
        XCTAssertTrue(drink.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Mystery")
        XCTAssertTrue(drink.exists)
        drink.tap()
        XCTAssertFalse(app.buttons["confirmLogDrink"].isEnabled)
    }

    func testConfirmedLogSurvivesTemplateEditAndDeletion() {
        let app = launch(["--seed-library"])
        app.tabBars.buttons["Drinks"].tap()
        app.buttons["drink.Iced Mocha"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForExistence(timeout: 5))
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.tabBars.buttons["Drinks"].waitForExistence(timeout: 5))
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Edit Drink"].tap()
        replace(app.textFields["nutrition.caffeine"], with: "110")
        capture("Editor-Caffeine-Keyboard", app)
        app.buttons["saveDrink"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~100 mg caffeine")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~110 mg caffeine")).firstMatch.exists)
        app.tabBars.buttons["Drinks"].tap()
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Delete Drink"].tap()
        app.buttons["Delete Drink"].tap()
        XCTAssertFalse(app.buttons["drink.Iced Mocha"].exists)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~100 mg caffeine")).firstMatch.exists)
    }

    func testQuickAddCanLogCaffeineOnlyAndSaveReusableDrink() {
        let app = launch()
        app.tabBars.buttons["Drinks"].tap()
        app.buttons["Quick Add"].tap()
        let caffeine = app.textFields["nutrition.caffeine"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tap(); caffeine.typeText("80")
        XCTAssertEqual(caffeine.value as? String, "80")
        app.swipeUp()
        let reusable = app.switches["Save as reusable drink"]
        // SwiftUI exposes the label and switch as one accessibility row; tap the actual trailing switch.
        reusable.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(reusable.value as? String, "1")
        app.buttons["quickLogToHealth"].tap()
        XCTAssertTrue(app.buttons["quickLogToHealth"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["drink.Quick drink"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "80 mg caffeine")).firstMatch.waitForExistence(timeout: 5))
    }

    func testWritePermissionFailureDoesNotDismissOrCreateHistory() {
        let app = launch(["--seed-library", "--write-denied"])
        app.tabBars.buttons["Drinks"].tap()
        app.buttons["drink.Iced Mocha"].tap()
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.alerts["Couldn’t log drink"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].exists)
        app.navigationBars["Log Drink"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No visible nutrition yet"].exists)
    }

    func testQueryFailureAndUnavailableHealthKeepLibraryUsable() {
        var app = launch(["--query-failure"])
        app.buttons["chooseHealthAccess"].tap()
        XCTAssertTrue(app.staticTexts["Health refresh needs attention"].waitForExistence(timeout: 5))
        app.terminate()
        app = launch(["--health-unavailable", "--seed-library"])
        XCTAssertTrue(app.staticTexts["Apple Health unavailable"].exists)
        app.tabBars.buttons["Drinks"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].exists)
    }

    func testScreenshotsLight() {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        capture("Today-Light", app)
        app.swipeUp()
        capture("QuickLog-And-Trend-Light", app)
        app.tabBars.buttons["Drinks"].tap()
        capture("Drinks-Light", app)
        app.buttons["drink.Iced Mocha"].tap()
        capture("Confirmation-Light", app)
        app.navigationBars["Log Drink"].buttons["Cancel"].tap()
        app.buttons["addDrink"].tap()
        capture("Editor-Light", app)
        app.navigationBars["Add Drink"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        capture("History-Light", app)
        app.tabBars.buttons["Settings"].tap()
        capture("Settings-Light", app)
    }

    func testScreenshotsDark() {
        let app = launch(["--seed-library", "--populated-health", "--dark-mode"])
        connectFixture(app)
        capture("Today-Dark", app)
        app.tabBars.buttons["Drinks"].tap()
        capture("Drinks-Dark", app)
    }

    func testScreenshotsAccessibilityText() {
        let app = launch(["--seed-library", "--populated-health", "--large-text"])
        connectFixture(app)
        capture("Today-Accessibility3", app)
        app.tabBars.buttons["Drinks"].tap()
        capture("Drinks-Accessibility3", app)
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Wait for the previous process to exit before asking Xcode to create another automation session.
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        }
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        return app
    }
    private func connectFixture(_ app: XCUIApplication) {
        let button = app.buttons["chooseHealthAccess"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let total = app.staticTexts["todayCaffeine"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("225"))
    }
    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        if !field.isHittable { XCUIApplication().swipeUp() }
        field.tap()
        // Use the SDK's native hardware-key API rather than sending control-key strings as text.
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
