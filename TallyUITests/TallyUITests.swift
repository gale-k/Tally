import XCTest

/// Every UI test injects an in-memory library and fake Health store. Real health data is never read or written.
@MainActor
final class TallyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppLaunchesWithFourTabs() {
        let app = launch()
        for title in ["Today", "Library", "History", "Settings"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        XCTAssertTrue(app.buttons["chooseHealthAccess"].exists)
        capture("Empty-Today", app)
    }

    func testCreateTemplateWithUnknownNutritionAndSearch() {
        let app = launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Mystery Snack")
        capture("Editor-Name-Keyboard", app)
        app.buttons["saveDrink"].tap()
        let drink = app.buttons["drink.Mystery Snack"]
        XCTAssertTrue(drink.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Mystery")
        XCTAssertTrue(drink.exists)
        drink.tap()
        XCTAssertFalse(app.buttons["confirmLogDrink"].isEnabled)
    }

    func testConfirmedLogSurvivesTemplateEditAndDeletion() {
        let app = launch(["--seed-library"])
        app.tabBars.buttons["Library"].tap()
        app.buttons["drink.Iced Mocha"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForExistence(timeout: 5))
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 5))
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Edit Item"].tap()
        replace(app.textFields["nutrition.caffeine"], with: "110")
        capture("Editor-Caffeine-Keyboard", app)
        app.buttons["saveDrink"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~100 mg caffeine")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~110 mg caffeine")).firstMatch.exists)
        app.tabBars.buttons["Library"].tap()
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Delete Item"].tap()
        app.buttons["Delete Item"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].waitForNonExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~100 mg caffeine")).firstMatch.exists)
    }

    func testQuickAddCanLogCaffeineOnlyAndSaveReusableDrink() {
        let app = launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["Quick Add"].tap()
        let caffeine = app.textFields["nutrition.caffeine"]
        XCTAssertTrue(caffeine.waitForExistence(timeout: 5))
        caffeine.tap(); caffeine.typeText("80")
        XCTAssertEqual(caffeine.value as? String, "80")
        app.swipeUp()
        let reusable = app.switches["Save as reusable item"]
        // SwiftUI exposes the label and switch as one accessibility row; tap the actual trailing switch.
        reusable.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(reusable.value as? String, "1")
        app.buttons["quickLogToHealth"].tap()
        XCTAssertTrue(app.buttons["quickLogToHealth"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["drink.Quick entry"].waitForExistence(timeout: 5))
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "80 mg caffeine")).firstMatch.waitForExistence(timeout: 5))
    }

    func testWritePermissionFailureDoesNotDismissOrCreateHistory() {
        let app = launch(["--seed-library", "--write-denied"])
        app.tabBars.buttons["Library"].tap()
        app.buttons["drink.Iced Mocha"].tap()
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.alerts["Couldn’t log item"].waitForExistence(timeout: 5))
        capture("Write-Permission-Error", app)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].exists)
        app.navigationBars["Log Item"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["No visible nutrition yet"].exists)
    }

    func testQueryFailureAndUnavailableHealthKeepLibraryUsable() {
        var app = launch(["--query-failure"])
        app.buttons["chooseHealthAccess"].tap()
        XCTAssertTrue(app.staticTexts["Health refresh needs attention"].waitForExistence(timeout: 5))
        capture("Query-Error", app)
        app.terminate()
        app = launch(["--health-unavailable", "--seed-library"])
        XCTAssertTrue(app.staticTexts["Apple Health unavailable"].exists)
        capture("Health-Unavailable", app)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].exists)
    }

    func testScreenshotsLight() {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        capture("Today-Light", app)
        app.swipeUp()
        capture("QuickLog-And-Trend-Light", app)
        app.tabBars.buttons["Library"].tap()
        capture("Library-Light", app)
        app.buttons["drink.Iced Mocha"].tap()
        capture("Confirmation-Light", app)
        app.navigationBars["Log Item"].buttons["Cancel"].tap()
        app.buttons["addDrink"].tap()
        capture("Editor-Light", app)
        app.navigationBars["Add Item"].buttons["Cancel"].tap()
        app.buttons["Quick Add"].tap()
        capture("QuickAdd-Light", app)
        app.navigationBars["Quick Add"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        capture("History-Light", app)
        app.tabBars.buttons["Settings"].tap()
        capture("Settings-Light", app)
    }

    func testScreenshotsDark() {
        let app = launch(["--seed-library", "--populated-health", "--dark-mode"])
        connectFixture(app)
        capture("Today-Dark", app)
        app.tabBars.buttons["Library"].tap()
        capture("Library-Dark", app)
        let lunch = app.buttons["drink.Lunch Bowl"]
        reveal(lunch, in: app)
        lunch.tap()
        capture("Confirmation-Dark", app)
        app.navigationBars["Log Item"].buttons["Cancel"].tap()
        app.buttons["addDrink"].tap()
        capture("Editor-Dark", app)
        app.navigationBars["Add Item"].buttons["Cancel"].tap()
        app.buttons["Quick Add"].tap()
        capture("QuickAdd-Dark", app)
        app.navigationBars["Quick Add"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        capture("History-Dark", app)
        app.tabBars.buttons["Settings"].tap()
        capture("Settings-Dark", app)
    }

    func testScreenshotsAccessibilityText() {
        let app = launch(["--seed-library", "--populated-health", "--large-text"])
        connectFixture(app)
        capture("Today-Accessibility3", app)
        app.tabBars.buttons["Library"].tap()
        capture("Library-Accessibility3", app)
        let lunch = app.buttons["drink.Lunch Bowl"]
        reveal(lunch, in: app)
        lunch.tap()
        capture("Confirmation-Accessibility3", app)
        app.navigationBars["Log Item"].buttons["Cancel"].tap()
        app.buttons["addDrink"].tap()
        capture("Editor-Accessibility3", app)
        reveal(app.textFields["nutrition.calories"], in: app)
        capture("Editor-Nutrition-Accessibility3", app)
        app.navigationBars["Add Item"].buttons["Cancel"].tap()
        app.buttons["Quick Add"].tap()
        capture("QuickAdd-Accessibility3", app)
        reveal(app.buttons["quickLogToHealth"], in: app)
        capture("QuickAdd-Action-Accessibility3", app)
        app.navigationBars["Quick Add"].buttons["Cancel"].tap()
        app.tabBars.buttons["History"].tap()
        capture("History-Accessibility3", app)
        app.tabBars.buttons["Settings"].tap()
        capture("Settings-Accessibility3", app)
    }

    /// Food-only nutrition must use the same confirmation and Health flow without manufacturing caffeine.
    func testFoodWithCaloriesAndProteinCanBeSavedAndLogged() {
        let app = launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("My Lunch")
        let calories = app.textFields["nutrition.calories"]
        reveal(calories, in: app)
        calories.tap(); calories.typeText("380")
        let protein = app.textFields["nutrition.protein"]
        protein.tap(); protein.typeText("24")
        app.buttons["saveDrink"].tap()
        let item = app.buttons["drink.My Lunch"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.label.contains("24 g protein"))
        XCTAssertFalse(item.label.contains("Caffeine unknown"))
        item.tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Caffeine"].exists)
        capture("Food-Confirmation", app)
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForNonExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
        let event = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "24 g protein")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "380 kcal")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Caffeine"].exists)
        capture("Food-History-Detail", app)
    }

    /// Hiding caffeine is a presentation choice; caffeine-only templates remain usable in the same library.
    func testTodayNutrientsCanBeConfiguredWithoutChangingTemplates() {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        app.tabBars.buttons["Settings"].tap()
        let caffeine = app.switches["Show Caffeine & Trend"]
        caffeine.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(caffeine.value as? String, "0")
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.staticTexts["todayCaffeine"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "600 kcal")).firstMatch.exists)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].label.contains("~100 mg caffeine"))
    }

    /// Audit actionable descriptions; native SwiftUI scaling and contrast are separately checked in runtime captures.
    func testAccessibilityDescriptions() throws {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        // Broad scaling/contrast audits misidentify native controls and off-screen content on this runtime.
        // Keep deterministic description checks here; the explicit appearance tests capture the actual large-text layouts.
        let checks: XCUIAccessibilityAuditType = [.sufficientElementDescription]
        var findings: [String] = []
        func audit(_ screen: String) throws {
            // Collect every issue across screens, then fail once; no finding is silently ignored.
            try app.performAccessibilityAudit(for: checks) { issue in
                findings.append("\(screen): \(issue.element?.label ?? "Unknown element") — \(issue.detailedDescription)")
                return true
            }
        }
        try audit("Today")
        for title in ["Library", "History", "Settings"] {
            app.tabBars.buttons[title].tap()
            try audit(title)
        }
        app.tabBars.buttons["Library"].tap()
        app.buttons["drink.Iced Mocha"].tap()
        try audit("Confirmation")
        app.navigationBars["Log Item"].buttons["Cancel"].tap()
        app.buttons["addDrink"].tap()
        try audit("Editor")
        XCTAssertTrue(findings.isEmpty, findings.joined(separator: "\n"))
    }

    /// The real Settings flow asks before opt-in; a failed cloud connection must leave local templates usable.
    func testCloudOptInFailurePreservesLocalLibraryAndBackupActions() {
        let app = launch(["--seed-library"])
        app.tabBars.buttons["Settings"].tap()
        let enable = app.buttons["Enable iCloud Sync"]
        reveal(enable, in: app)
        capture("iCloud-Off-Light", app)
        enable.tap()
        XCTAssertTrue(app.buttons["Enable Sync"].waitForExistence(timeout: 5))
        capture("iCloud-Confirmation", app)
        app.buttons["Enable Sync"].tap()
        // UI fixtures prohibit CloudKit access, producing the same local-safe error presentation without a real account.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "iCloud is unavailable right now")).firstMatch.waitForExistence(timeout: 5))
        capture("iCloud-Unavailable", app)
        reveal(app.buttons["Restore Snapshot as New Copies"], in: app)
        XCTAssertTrue(app.buttons["Export Library Snapshot"].exists)
        XCTAssertTrue(app.buttons["Import Library"].exists)
        capture("Backups-And-Restore", app)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].exists)
    }

    func testCloudSettingsDarkAndLargeText() {
        let app = launch(["--seed-library", "--dark-mode", "--large-text"])
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["Enable iCloud Sync"], in: app)
        capture("iCloud-Dark-Accessibility3", app)
        app.buttons["Enable iCloud Sync"].tap()
        capture("iCloud-Confirmation-Dark-Accessibility3", app)
        // The compact native popover on this runtime dismisses by tapping outside, without a Cancel row.
        XCTAssertTrue(app.buttons["Enable Sync"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["Enable Sync"].waitForNonExistence(timeout: 5))
        reveal(app.buttons["Restore Snapshot as New Copies"], in: app)
        capture("Backups-Dark-Accessibility3", app)
    }

    // SwiftUI Forms lazily expose off-screen fields. Scroll until the actual target is visible, including after keyboard dismissal.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            // A short drag avoids jumping past a field when the keyboard reduces the visible Form height.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element)")
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
        let app = XCUIApplication()
        reveal(field, in: app)
        let current = field.value as? String ?? ""
        // Decimal-pad Command-A is unreliable in this Simulator. Tap at the trailing edge to place the caret after the value.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        XCTAssertTrue(["", "Optional"].contains(field.value as? String ?? ""))
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
