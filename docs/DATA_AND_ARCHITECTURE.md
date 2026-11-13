# Data and architecture

## Ownership

`SavedDrink` is the only SwiftData model. It stores template details, optional nutrient amounts, per-nutrient estimate markers, favourites, and convenience usage statistics. The single local `ModelContainer` explicitly disables CloudKit. Editors use a `DrinkDraft` snapshot and commit through `DrinkLibrary`; saves surface errors and roll back failed local changes.

`NutritionValues` and `Nutrient` centralise optional semantics, display, units, and input validation. User-entered nutrition must be finite and nonnegative. Typing-error bounds are 10,000 mg caffeine, 50,000 kcal, and 10,000 g for each other nutrient; these are input constraints, not health guidance. The optional volume must be greater than zero and at most 100,000 ml.

`NutritionStore` abstracts Health operations. `HealthKitStore` is the system adapter, while `HealthKitManager` coordinates transient query results and saving state. The views receive that manager through the SwiftUI environment. Health history is never persisted as a second database.

## Saving a consumption event

Confirmation creates an independent `ConsumptionDraft`, with one UUID and one timestamp. Only present values become `HKQuantitySample`s. Caffeine uses `gramUnit(with: .milli)`, energy uses `kilocalorie()`, and other supported nutrients use `gram()`.

The adapter checks Health availability and exposed write authorization for every present nutrient. It saves the complete sample array in one call. The installed SDK documents that if any object cannot be saved, none of that array is saved. This avoids silently logging only part of a drink when permissions are incomplete.

Samples use `HKMetadataKeyFoodType` and `HKMetadataKeyWasUserEntered`, plus reverse-DNS custom keys for event ID, brand, size, and that sample’s estimate flag. No local template relationship is required to read the historical event later.

After Health succeeds, the local template’s usage count and most recent consumption time are updated. A local save failure cannot undo the successful Health write: the sheet explicitly says the drink was saved to Health, prevents another submission, and reports the local issue. Quick Add uses the same ordering when creating an optional reusable template.

## Queries, privacy, and grouping

The adapter requests exactly the eight supported quantity types. `isHealthDataAvailable()` gates access. Permission-sheet completion is recorded only as “permissions requested”; it never becomes a universal read-authorized flag. Write statuses are displayed only where HealthKit exposes them.

The iOS 27 `earliestAuthorizedSampleDate(for:)` API clamps queries for types with a limited read window. An omitted type cannot distinguish full access from denial. Missing samples remain missing, including in daily cards and chart bars.

Recent history is a rolling window of 30 calendar days. Totals sum visible samples from all sources; day boundaries use the current calendar and half-open intervals, including daylight-saving transitions. The seven-day chart preserves estimate markers and omits bars when no sample is visible.

Only samples whose source bundle matches Tally may be grouped by Tally event metadata. Legacy Tally samples without an event identifier may be grouped by their exact timestamp. Every other app’s sample remains separate, even if it has copied metadata or a matching timestamp. The source name remains visible. History details expose all available nutrients.

The dashboard refreshes after logging, when returning to the foreground, and on pull-to-refresh. Refresh generations prevent a stale overlapping response from replacing a newer response. Query failures remain visible alongside any previously refreshed data and its timestamp.

## Library JSON, version 1

The root object has `version: 1` and `drinks: [SavedDrinkRecord]`. Records include identity, template details, nutrition and estimate flags, favourites, and creation/update timestamps. Dates use ISO 8601. There are no Health samples, consumption timestamps, or usage counts in the export. Imported templates start with a zero usage count and no last-logged date.

Import validates the complete document before insertion. Duplicate IDs within a file, unsupported versions, malformed or invalid data, files over 5 MB, and libraries over 5,000 records fail without importing a partial library. Existing UUIDs are skipped rather than overwritten. Missing records are saved in one SwiftData batch. Import never writes to Health.

## Development fixtures

`DevelopmentData.swift` contains only the seven requested Debug presets. The persistent once-only marker is set after a successful batch save. Normal app launches do not auto-seed.

`UITestFixtures.swift` is Debug-only. `--ui-testing` selects an in-memory SwiftData store and `FixtureNutritionStore`. Additional arguments select seeded templates, synthetic history, dark appearance, accessibility text sizes, and permission/query failure states. These test arguments and synthetic health samples do not exist in Release behavior.

Shortcuts, widgets, controls, photos, and undo are optional follow-up features; the core app does not expose them.
