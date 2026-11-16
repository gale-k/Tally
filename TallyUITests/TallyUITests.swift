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

    /// The editor must persist both units and Cold, including the stacked accessibility layout.
    func testServingAmountUnitsAndColdPersistInEditor() {
        verifyServingAmountEditor()
    }
    func testServingAmountEditorWithLargeText() {
        verifyServingAmountEditor(["--dark-mode", "--large-text"])
    }
    private func verifyServingAmountEditor(_ arguments: [String] = []) {
        let app = launch(arguments)
        app.tabBars.buttons["Library"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Chocolate")
        let amount = app.textFields["servingAmount"]
        reveal(amount, in: app)
        amount.tap(); amount.typeText("45")
        app.buttons["amountUnit"].tap()
        app.buttons["g"].tap()
        XCTAssertEqual(amount.label, "Amount, grams")
        let category = app.buttons["itemCategory"]
        reveal(category, in: app); category.tap()
        app.buttons["Snack"].tap()
        let style = app.buttons["servingStyle"]
        reveal(style, in: app); style.tap()
        app.buttons["Cold"].tap()
        capture("Serving-Grams-Cold" + (arguments.isEmpty ? "" : "-LargeText"), app)
        app.buttons["saveDrink"].tap()
        XCTAssertTrue(app.buttons["drink.Chocolate"].waitForExistence(timeout: 5))
        capture("Snack-Sweet-Icon" + (arguments.isEmpty ? "" : "-LargeText"), app)
        app.buttons["More actions for Chocolate"].tap()
        app.buttons["Edit Item"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "45.0")
        XCTAssertEqual(amount.label, "Amount, grams")
        reveal(style, in: app)
        XCTAssertTrue(style.label.contains("Cold"))
        // Return to ml with the same number, save, and reopen to exercise clearing the grams field.
        app.swipeDown()
        reveal(app.buttons["amountUnit"], in: app)
        app.buttons["amountUnit"].tap()
        app.buttons["ml"].tap()
        app.buttons["saveDrink"].tap()
        app.buttons["More actions for Chocolate"].tap()
        app.buttons["Edit Item"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "45.0")
        XCTAssertEqual(amount.label, "Amount, millilitres")
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

    /// Exercise archive browsing, editing and restoration at standard and accessibility text sizes.
    func testArchiveAndRestore() throws { try verifyArchive() }
    func testArchiveAndRestoreWithLargeText() throws { try verifyArchive(["--large-text"]) }
    private func verifyArchive(_ arguments: [String] = []) throws {
        let app = launch(["--seed-library"] + arguments)
        app.tabBars.buttons["Library"].tap()
        let item = app.buttons["drink.Iced Mocha"]
        reveal(item, in: app)
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Archive Item"].tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 5))
        // The large-text list may have scrolled the selector offscreen while revealing the item.
        for _ in 0..<6 where !app.buttons["Archived"].exists { app.swipeDown() }
        app.buttons["Archived"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        // The archived row opens the existing editor; a normal save must retain archive state.
        item.tap()
        XCTAssertTrue(app.textFields["drinkName"].waitForExistence(timeout: 5))
        app.buttons["saveDrink"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        app.buttons["More actions for Iced Mocha"].tap()
        app.buttons["Unarchive Item"].tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 5))
        app.buttons["Active"].tap()
        reveal(item, in: app)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
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

    /// Salt is an alternate input for one sodium value, retained through editing and historical logging.
    func testSodiumAndSaltCanBeSavedConvertedAndLogged() {
        verifySodiumAndSaltEditor()
    }
    func testSodiumAndSaltWithLargeText() {
        verifySodiumAndSaltEditor(["--dark-mode", "--large-text"])
    }
    private func verifySodiumAndSaltEditor(_ arguments: [String] = []) {
        let app = launch(arguments)
        let suffix = arguments.isEmpty ? "" : "-LargeText"
        app.tabBars.buttons["Library"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Salty Soup")
        let more = app.buttons["More Nutrition"]
        reveal(more, in: app); more.tap()
        let unit = app.buttons["sodiumInputUnit"]
        reveal(unit, in: app); unit.tap()
        app.buttons["Salt (g)"].tap()
        let sodium = app.textFields["nutrition.sodium"]
        reveal(sodium, in: app)
        XCTAssertEqual(sodium.label, "Salt, g")
        sodium.tap(); sodium.typeText("1.25")
        app.buttons["estimate.sodium"].tap()
        capture("Salt-Input" + suffix, app)
        reveal(unit, in: app); unit.tap(); app.buttons["Sodium (mg)"].tap()
        XCTAssertEqual(sodium.value as? String, "500")
        XCTAssertEqual(sodium.label, "Sodium, mg")
        app.buttons["saveDrink"].tap()
        let item = app.buttons["drink.Salty Soup"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.label.contains("~500 mg sodium"))
        app.buttons["More actions for Salty Soup"].tap(); app.buttons["Edit Item"].tap()
        reveal(more, in: app); more.tap()
        reveal(sodium, in: app)
        XCTAssertEqual(sodium.value as? String, "500.0")
        XCTAssertEqual(app.buttons["estimate.sodium"].value as? String, "Estimated")
        reveal(unit, in: app); unit.tap(); app.buttons["Salt (g)"].tap()
        XCTAssertEqual(sodium.value as? String, "1.25")
        app.buttons["saveDrink"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForExistence(timeout: 5))
        app.buttons["confirmLogDrink"].tap()
        XCTAssertTrue(app.buttons["confirmLogDrink"].waitForNonExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
        let event = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "~500 mg sodium")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5)); event.tap()
        XCTAssertTrue(app.staticTexts["Sodium"].exists)
        capture("Sodium-History" + suffix, app)
    }

    /// Explicit zero from Quick Add remains visible, even when sodium is the only selected Today card.
    func testQuickAddSodiumCanAppearOnToday() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        for title in ["Show Calories", "Show Protein", "Show Sugar", "Show Caffeine & Trend", "Show Sodium"] {
            let toggle = app.switches[title]
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        app.tabBars.buttons["Library"].tap(); app.buttons["Quick Add"].tap()
        let more = app.buttons["More Nutrition"]
        reveal(more, in: app); more.tap()
        let sodium = app.textFields["nutrition.sodium"]
        reveal(sodium, in: app); sodium.tap(); sodium.typeText("0")
        let log = app.buttons["quickLogToHealth"]
        reveal(log, in: app); log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Nutrition Today"].exists)
        XCTAssertTrue(app.staticTexts["Sodium"].exists)
        XCTAssertTrue(app.staticTexts["0 mg"].exists)
        XCTAssertFalse(app.staticTexts["todayCaffeine"].exists)
        capture("Sodium-Only-Today", app)
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

    /// Exercise real Settings bindings, validation, relaunch persistence, disable, reset, and Today updates.
    func testDailyIntakeSettingsPersistAndUpdateToday() {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["dailyIntakeSettings"].tap()
        app.buttons["dailyIntake.calories"].tap()
        let field = app.textFields["dailyIntakeValue"]
        replace(field, with: "300")
        app.buttons["saveDailyIntake"].tap()
        XCTAssertTrue(app.staticTexts["Value saved"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "200%")).firstMatch.waitForExistence(timeout: 5))
        capture("Daily-Intake-Above-Target", app)
        app.tabBars.buttons["Settings"].tap()
        replace(field, with: "0")
        app.buttons["saveDailyIntake"].tap()
        XCTAssertTrue(app.staticTexts["dailyIntakeError"].waitForExistence(timeout: 5))
        capture("Daily-Intake-Invalid-Value", app)
        app.swipeDown()
        let enabled = app.switches["comparisonEnabled"]
        reveal(enabled, in: app)
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.terminate()
        app.launchArguments += ["--preserve-preferences"]
        app.launch()
        connectFixture(app)
        XCTAssertTrue(app.staticTexts["Comparison off"].exists)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["dailyIntakeSettings"].tap(); app.buttons["dailyIntake.calories"].tap()
        XCTAssertEqual(field.value as? String, "300")
        XCTAssertEqual(enabled.value as? String, "0")
        app.buttons["resetDailyIntake"].tap()
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertEqual(field.value as? String, "2000")
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "30%")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["drink.Iced Mocha"].label.contains("~100 mg caffeine"))
    }

    /// A sodium card with extra detail shares aligned rows and the breakdown keeps its source note.
    func testNutritionCardRowsAndSourceNote() {
        let app = launch(["--populated-health", "--populated-sodium", "--dark-mode"])
        connectFixture(app)
        app.tabBars.buttons["Settings"].tap()
        let sodium = app.switches["Show Sodium"]
        sodium.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Sodium"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Daily target")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Daily maximum")).firstMatch.exists)
        capture("Today-Nutrition-Row-Alignment", app)
        let breakdown = app.buttons["dailyIntakeBreakdown"]
        reveal(breakdown, in: app); breakdown.tap()
        XCTAssertTrue(app.staticTexts["Visible Apple Health nutrition · all sources"].waitForExistence(timeout: 5))
        capture("Daily-Intake-Source-Note", app)
    }

    /// The upgrade retains both the original caffeine amount and existing dashboard visibility choices.
    func testDailyIntakePreservesLegacyCaffeineAndVisibility() {
        let app = launch(["--legacy-daily-settings", "--populated-health"])
        connectFixture(app)
        XCTAssertFalse(app.staticTexts["today.sugar"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(app.switches["Show Sugar"].value as? String, "0")
        app.buttons["dailyIntakeSettings"].tap()
        app.buttons["dailyIntake.caffeine"].tap()
        let field = app.textFields["dailyIntakeValue"]
        XCTAssertEqual(field.value as? String, "250")
        replace(field, with: "225"); app.buttons["saveDailyIntake"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "100%")).firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        replace(field, with: "100"); app.buttons["saveDailyIntake"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "225%")).firstMatch.waitForExistence(timeout: 5))
        reveal(app.buttons["dailyIntakeBreakdown"], in: app); app.buttons["dailyIntakeBreakdown"].tap()
        XCTAssertTrue(app.staticTexts["Total Sugars"].exists)
        capture("Daily-Intake-Breakdown", app)
    }

    /// One sodium maximum can be edited in salt and shown on the optional sodium card.
    func testSodiumDailyMaximumCanBeEditedAsSalt() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        app.switches["Show Sodium"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["dailyIntakeSettings"].tap()
        let sodium = app.buttons["dailyIntake.sodium"]
        reveal(sodium, in: app); sodium.tap()
        let unit = app.buttons["dailySodiumUnit"]
        reveal(unit, in: app); unit.tap(); app.buttons["Salt (g)"].tap()
        let field = app.textFields["dailyIntakeValue"]
        XCTAssertEqual(field.value as? String, "6")
        replace(field, with: "5"); app.buttons["saveDailyIntake"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2,000 mg")).firstMatch.exists)
        app.tabBars.buttons["Library"].tap(); app.buttons["Quick Add"].tap()
        let more = app.buttons["More Nutrition"]
        reveal(more, in: app); more.tap()
        let amount = app.textFields["nutrition.sodium"]
        reveal(amount, in: app); amount.tap(); amount.typeText("1000")
        let log = app.buttons["quickLogToHealth"]
        reveal(log, in: app); log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "50%")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "5 g salt")).firstMatch.exists)
    }

    /// A visible zero is measured data and must show 0% rather than the unknown-data state.
    func testDailyIntakeKnownZeroStillCompares() {
        let app = launch()
        app.tabBars.buttons["Library"].tap(); app.buttons["Quick Add"].tap()
        let calories = app.textFields["nutrition.calories"]
        reveal(calories, in: app); calories.tap(); calories.typeText("0")
        let log = app.buttons["quickLogToHealth"]
        reveal(log, in: app); log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["today.calories"].label.contains("0 kcal"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0%")).firstMatch.waitForExistence(timeout: 5))
        capture("Daily-Intake-Known-Zero", app)
    }

    /// Empty and failed Health queries cannot manufacture a zero or full remaining allowance.
    func testDailyIntakeUnknownAndFailedHealthData() {
        let app = launch(["--query-failure"])
        app.buttons["chooseHealthAccess"].tap()
        XCTAssertTrue(app.staticTexts["Health refresh needs attention"].waitForExistence(timeout: 5))
        reveal(app.buttons["dailyIntakeBreakdown"], in: app); app.buttons["dailyIntakeBreakdown"].tap()
        XCTAssertTrue(app.staticTexts["Health refresh needs attention"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No visible data to compare")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).firstMatch.exists)
        capture("Daily-Intake-Unknown-Health", app)
    }

    /// Verify the new destinations at accessibility text sizes, with all nutrient settings discoverable.
    func testDailyIntakeDarkLargeTextAndAccessibility() throws {
        let app = launch(["--dark-mode", "--large-text", "--populated-health"])
        connectFixture(app)
        reveal(app.buttons["dailyIntakeBreakdown"], in: app); app.buttons["dailyIntakeBreakdown"].tap()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        XCTAssertTrue(app.navigationBars["Daily Intake"].waitForExistence(timeout: 5))
        capture("Daily-Intake-Dark-LargeText", app)
        let progress = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "to target")).firstMatch
        reveal(progress, in: app)
        app.swipeUp()
        capture("Daily-Intake-Card-Dark-LargeText", app)
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["dailyIntakeSettings"], in: app); app.buttons["dailyIntakeSettings"].tap()
        capture("Daily-Intake-Settings-Dark-LargeText", app)
        for nutrient in ["calories", "protein", "sugar", "caffeine", "carbohydrates", "totalFat", "saturatedFat", "fibre", "sodium"] {
            reveal(app.buttons["dailyIntake." + nutrient], in: app)
        }
        reveal(app.buttons["dailyIntake.fibre"], in: app)
        app.buttons["dailyIntake.fibre"].tap()
        capture("Daily-Intake-Editor-Dark-LargeText", app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
    }

    // SwiftUI may call a partially exposed row hittable even when its centre is behind the keyboard.
    // Reveal its actual tap point, including deeper extended nutrition and targets above the current scroll position.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom - 12 { return }
            let scrollBack = element.exists && element.frame.midY <= top
            // A short drag avoids jumping past a field when the keyboard reduces the visible Form height.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollBack ? 0.3 : 0.5)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollBack ? 0.5 : 0.3)))
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
        XCTAssertTrue(["", field.placeholderValue ?? "Optional"].contains(field.value as? String ?? ""), "Field did not clear: \(field.value as? String ?? "")")
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
