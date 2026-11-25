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

    /// The appearance preference starts at System and survives a fresh app launch.
    func testAppearanceSelectionPersists() {
        var app = launch(["--test-appearance-setting"])
        app.tabBars.buttons["Settings"].tap()
        let dark = app.buttons["Dark"]
        reveal(dark, in: app)
        XCTAssertTrue(app.buttons["System"].isSelected)
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        app.terminate()
        app = launch(["--test-appearance-setting", "--preserve-preferences"])
        app.tabBars.buttons["Settings"].tap()
        reveal(app.buttons["Dark"], in: app)
        XCTAssertTrue(app.buttons["Dark"].isSelected)
        app.buttons["Light"].tap()
        XCTAssertTrue(app.buttons["Light"].isSelected)
        app.buttons["System"].tap()
        XCTAssertTrue(app.buttons["System"].isSelected)
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

    /// The separate editor stages text only on Done. Saved recipes remain searchable after archiving.
    func testRecipeBookFromLibraryItem() throws { try verifyRecipeBook() }
    func testRecipeBookWithLargeText() throws { try verifyRecipeBook(["--dark-mode", "--large-text"]) }

    private func verifyRecipeBook(_ arguments: [String] = []) throws {
        let app = launch(arguments)
        let itemName = "Berry Bowl"
        let item = app.buttons["drink.\(itemName)"]
        let actions = app.buttons["More actions for \(itemName)"]
        let book = app.buttons["openRecipeBook"]
        let recipe = app.buttons["recipe.\(itemName)"]
        let openEditor = app.buttons["openRecipeEditor"]
        let recipeWindow = app.navigationBars["Recipe"]
        let ingredients = app.textFields["recipeIngredients"]
        let method = app.textFields["recipeMethod"]
        app.tabBars.buttons["Library"].tap()
        app.buttons["addDrink"].tap()
        let name = app.textFields["drinkName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText(itemName)
        let homemade = app.switches["homemade"]
        reveal(homemade, in: app)
        homemade.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(homemade.value as? String, "1")
        reveal(openEditor, in: app)
        XCTAssertEqual(openEditor.label, "Add Recipe")
        XCTAssertFalse(ingredients.exists)
        openEditor.tap()
        XCTAssertTrue(recipeWindow.waitForExistence(timeout: 5))
        reveal(ingredients, in: app)
        ingredients.tap(); ingredients.typeText("Draft only")
        recipeWindow.buttons["Cancel"].tap()
        XCTAssertTrue(recipeWindow.waitForNonExistence(timeout: 5))
        app.buttons["saveDrink"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.label.contains("Homemade"))
        reveal(book, in: app); book.tap()
        XCTAssertTrue(app.staticTexts["No recipes yet"].waitForExistence(timeout: 5))
        app.navigationBars["Recipe Book"].buttons.firstMatch.tap()

        reveal(actions, in: app)
        actions.tap()
        app.buttons["Edit Item"].tap()
        reveal(openEditor, in: app); openEditor.tap()
        XCTAssertTrue(recipeWindow.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        reveal(ingredients, in: app)
        ingredients.tap(); ingredients.typeText("80 g oats\n150 ml milk")
        reveal(method, in: app)
        method.tap(); method.typeText("Mix and chill.")
        capture(arguments.isEmpty ? "Recipe-Editor" : "Recipe-Editor-Dark-LargeText", app)
        app.buttons["doneRecipe"].tap()
        XCTAssertTrue(recipeWindow.waitForNonExistence(timeout: 5))
        reveal(openEditor, in: app)
        XCTAssertEqual(openEditor.label, "Edit Recipe")
        app.buttons["saveDrink"].tap()
        reveal(book, in: app); book.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        XCTAssertTrue(app.navigationBars[itemName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "80 g oats", "150 ml milk")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Mix and chill."].exists)
        capture(arguments.isEmpty ? "Recipe-Detail" : "Recipe-Detail-Dark-LargeText", app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])

        // Done updates the item draft, so cancelling Edit Item still leaves the book unchanged.
        app.buttons["editRecipeItem"].tap()
        reveal(openEditor, in: app); openEditor.tap()
        XCTAssertTrue(recipeWindow.waitForExistence(timeout: 5))
        reveal(method, in: app)
        XCTAssertEqual(method.value as? String, "Mix and chill.")
        method.tap(); method.typeText(" Do not save this.")
        app.buttons["doneRecipe"].tap()
        XCTAssertTrue(recipeWindow.waitForNonExistence(timeout: 5))
        app.navigationBars["Edit Item"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Mix and chill."].waitForExistence(timeout: 5))
        app.navigationBars[itemName].buttons.firstMatch.tap()
        app.navigationBars["Recipe Book"].buttons.firstMatch.tap()

        reveal(actions, in: app)
        actions.tap()
        app.buttons["Archive Item"].tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 5))
        reveal(book, in: app); book.tap()
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        XCTAssertTrue(recipe.label.contains("Archived"))
        if arguments.isEmpty { capture("Recipe-Book", app) }
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("oats")
        XCTAssertTrue(recipe.exists)
        search.typeText("xyz")
        XCTAssertTrue(recipe.waitForNonExistence(timeout: 5))
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
        capture("QuickLog-Light", app)
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

    /// A positive sodium amount from Quick Add appears even when sodium is the only selected Today card.
    func testQuickAddSodiumCanAppearOnToday() {
        let app = launch()
        app.tabBars.buttons["Settings"].tap()
        for title in ["Show Calories", "Show Protein", "Show Sugar", "Show Caffeine Card", "Show Sodium"] {
            let toggle = app.switches[title]
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        app.tabBars.buttons["Library"].tap(); app.buttons["Quick Add"].tap()
        let more = app.buttons["More Nutrition"]
        reveal(more, in: app); more.tap()
        let sodium = app.textFields["nutrition.sodium"]
        reveal(sodium, in: app); sodium.tap(); sodium.typeText("500")
        let log = app.buttons["quickLogToHealth"]
        reveal(log, in: app); log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Nutrition Today"].exists)
        XCTAssertTrue(app.staticTexts["Sodium"].exists)
        XCTAssertTrue(app.staticTexts["500 mg"].exists)
        XCTAssertFalse(app.staticTexts["todayCaffeine"].exists)
        capture("Sodium-Only-Today", app)
    }

    /// Hiding caffeine is a presentation choice; caffeine-only templates remain usable in the same library.
    func testTodayNutrientsCanBeConfiguredWithoutChangingTemplates() {
        let app = launch(["--seed-library", "--populated-health"])
        connectFixture(app)
        app.tabBars.buttons["Settings"].tap()
        let caffeine = app.switches["Show Caffeine Card"]
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

    /// Both summary surfaces open the selected nutrient using the same synthetic Health snapshot.
    func testNutrientContributionNavigation() {
        let app = launch(["--populated-health"])
        connectFixture(app)
        app.buttons["nutrientContributions.calories"].tap()
        XCTAssertTrue(app.navigationBars["Calories"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contributionTotal"].label.contains("600 kcal"))
        XCTAssertTrue(app.staticTexts["Iced Mocha"].exists)
        XCTAssertTrue(app.staticTexts["Lunch Bowl"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["dailyIntakeBreakdown"], in: app); app.buttons["dailyIntakeBreakdown"].tap()
        let fibre = app.buttons["nutrientContributions.fibre"]
        reveal(fibre, in: app); fibre.tap()
        XCTAssertTrue(app.navigationBars["Fibre"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contributionTotal"].label.contains("6 g"))
        XCTAssertTrue(app.staticTexts["Lunch Bowl"].exists)
    }

    /// The contribution page remains navigable and described at accessibility text sizes.
    func testNutrientContributionDarkLargeTextAccessibility() throws {
        let app = launch(["--populated-health", "--dark-mode", "--large-text"])
        connectFixture(app)
        let calories = app.buttons["nutrientContributions.calories"]
        reveal(calories, in: app); calories.tap()
        XCTAssertTrue(app.navigationBars["Calories"].waitForExistence(timeout: 5))
        capture("Nutrient-Contributions-Dark-LargeText", app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
    }

    // A hidden Today nutrient is selectable in History and retains its range and day after drill-down.
    func testNutritionTrendsPersistsNutrientAndReconcilesDatedContributions() {
        let app = launch(["--populated-health", "--trend-fixture"])
        connectFixture(app)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Last 30 days"].waitForExistence(timeout: 5))
        app.buttons["Trends"].tap()
        let picker = app.buttons["trendNutrient"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Caffeine")
        XCTAssertTrue(app.staticTexts["trendSelectedDate"].label.contains("today so far"))
        picker.tap()
        app.buttons["Sodium"].tap()
        XCTAssertEqual(picker.value as? String, "Sodium")
        let chart = app.descendants(matching: .any)["nutritionTrendChart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        // Tap yesterday's slot above the baseline to exercise chart selection separately from the day picker.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.45)).tap()
        XCTAssertEqual(app.staticTexts["trendSelectedTotal"].label, "0 mg")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45)).tap()
        XCTAssertEqual(app.staticTexts["trendSelectedTotal"].label, "No visible data")
        XCTAssertTrue(app.staticTexts["Outside the Apple Health read window."].exists)
        let coverage = app.staticTexts["trendCoverage"]
        reveal(coverage, in: app)
        XCTAssertEqual(coverage.label, "2 of 6 completed days with data")
        XCTAssertTrue(app.staticTexts["trendAverage"].label.contains("250 mg"))

        selectTrendDay(containing: "~500 mg", spoken: "Approximately 500 mg", in: app)
        let selectedDate = app.staticTexts["trendSelectedDate"].label
        XCTAssertTrue(app.staticTexts["trendSelectedTotal"].label.contains("500 mg"))
        XCTAssertTrue(app.staticTexts["Apple Health only shares part of this day."].exists)
        let month = app.buttons["30 days"]
        reveal(month, in: app)
        month.tap()
        XCTAssertEqual(app.staticTexts["trendSelectedDate"].label, selectedDate)
        capture("Trends-Sodium-30-days-Light", app)
        let contributions = app.buttons["viewTrendContributions"]
        reveal(contributions, in: app)
        contributions.tap()
        XCTAssertTrue(app.navigationBars["Sodium"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["contributionTotal"].label.contains("500 mg"))
        XCTAssertTrue(app.staticTexts["Soup"].exists)
        XCTAssertTrue(app.staticTexts["Unnamed nutrition entry"].exists)
        XCTAssertTrue(app.staticTexts["Other Nutrition"].exists)
        capture("Trends-Dated-Contributions-Light", app)
        app.navigationBars["Sodium"].buttons.firstMatch.tap()
        XCTAssertEqual(app.staticTexts["trendSelectedDate"].label, selectedDate)
        XCTAssertEqual(coverage.label, "2 of 29 completed days with data")
        // The detail's own shortcut pops back to the same History stack.
        reveal(contributions, in: app)
        contributions.tap()
        app.buttons["openNutrientTrend"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trendSelectedDate"].label, selectedDate)

        app.terminate()
        app.launchArguments += ["--preserve-preferences"]
        app.launch()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Last 30 days"].waitForExistence(timeout: 5))
        app.buttons["Trends"].tap()
        XCTAssertEqual(picker.value as? String, "Sodium")
    }

    // Test native accessibility descriptions, the shortcuts, and the visible zero at large text sizes.
    func testNutritionTrendShortcutsAndZeroAtLargeTextInDarkMode() throws {
        let app = launch(["--populated-health", "--trend-fixture", "--dark-mode", "--large-text"])
        connectFixture(app)
        let shortcut = app.buttons["openNutritionTrends"]
        reveal(shortcut, in: app)
        shortcut.tap()
        let picker = app.buttons["trendNutrient"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Caffeine")
        picker.tap()
        app.buttons["Sodium"].tap()
        app.buttons["30 days"].tap()
        app.buttons["7 days"].tap()
        capture("Trends-Sodium-Chart-Dark-Accessibility3", app)
        selectTrendDay(containing: "0 mg", in: app)
        let total = app.staticTexts["trendSelectedTotal"]
        XCTAssertEqual(total.label, "0 mg")
        let contributions = app.buttons["viewTrendContributions"]
        reveal(contributions, in: app)
        capture("Trends-Sodium-Zero-Dark-Accessibility3", app)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription])
        contributions.tap()
        XCTAssertEqual(app.staticTexts["contributionTotal"].label, "0 mg")
        XCTAssertTrue(app.staticTexts["Plain water"].exists)

        app.tabBars.buttons["Today"].tap()
        let calories = app.buttons["nutrientContributions.calories"]
        reveal(calories, in: app)
        calories.tap()
        let viewTrend = app.buttons["openNutrientTrend"]
        reveal(viewTrend, in: app)
        viewTrend.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Calories")
    }

    func testNutritionTrendsExplainsEmptyDataAndUnavailableAverage() {
        let app = launch()
        app.tabBars.buttons["History"].tap()
        app.buttons["Trends"].tap()
        app.buttons["chooseHealthAccess"].tap()
        XCTAssertTrue(app.staticTexts["trendEmpty"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trendSelectedTotal"].label, "No visible data")
        XCTAssertEqual(app.staticTexts["trendAverage"].label, "No average available")
        XCTAssertEqual(app.staticTexts["trendCoverage"].label, "0 of 6 completed days with data")
    }

    private func selectTrendDay(containing amount: String, spoken: String? = nil, in app: XCUIApplication) {
        let choose = app.buttons["chooseTrendDay"]
        reveal(choose, in: app)
        choose.tap()
        let day = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@ OR label ENDSWITH %@",
                                                   ", " + amount, ", " + (spoken ?? amount))).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
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

    /// Quick Add requires a positive amount, and a denied zero-valued nutrient cannot block logging.
    func testQuickAddSkipsZeroNutrientsAndRejectsZeroOnlyEntries() {
        let app = launch(["--write-denied"])
        app.tabBars.buttons["Library"].tap(); app.buttons["Quick Add"].tap()
        let caffeine = app.textFields["nutrition.caffeine"]
        reveal(caffeine, in: app); caffeine.tap(); caffeine.typeText("0")
        let log = app.buttons["quickLogToHealth"]
        reveal(log, in: app); log.tap()
        let alert = app.alerts["Couldn’t log item"]
        XCTAssertTrue(alert.staticTexts["Enter at least one nutrient amount greater than zero to log to Apple Health."].waitForExistence(timeout: 5))
        alert.buttons["OK"].tap()

        let calories = app.textFields["nutrition.calories"]
        reveal(calories, in: app); calories.tap(); calories.typeText("50")
        reveal(log, in: app); log.tap()
        XCTAssertTrue(log.waitForNonExistence(timeout: 10))
        app.tabBars.buttons["History"].tap()
        let event = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "50 kcal")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        XCTAssertFalse(event.label.contains("caffeine"))
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
