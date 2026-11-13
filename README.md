# Tally

A native, caffeine-first iPhone app for keeping your usual drinks close and logging their known nutrition to Apple Health.

## What it does

- Save reusable drinks with favourites, brands, serving sizes, notes, and optional nutrition.
- Find a usual drink with search, category filters, five sort orders, and ranked Quick Log cards.
- Review a drink and its time before logging, or use Quick Add for a one-off drink.
- Track caffeine first, with optional calorie and sugar cards, recent Health history, and a seven-day chart.
- Export and import the local template library as JSON.

Supported nutrition: caffeine (mg), energy (kcal), sugar, carbohydrates, protein, total fat, saturated fat, and fibre (g). **Blank means unknown; zero is a real value.** Tap `~` beside a nutrition field to mark it as estimated.

## Preview

Local Simulator screenshots with synthetic test data, not personal Health history.

| Light | Dark |
| --- | --- |
| <img src="docs/images/today-light.png" width="260" alt="Tally Today in light mode"> | <img src="docs/images/today-dark.png" width="260" alt="Tally Today in dark mode"> |

## Getting started

1. Open `Tally.xcodeproj` in Xcode 27.0 or later. The project uses the installed iOS 27 SDK and requires iOS 27.0 or later.
2. Select your Apple development team if necessary. HealthKit and its read/write purpose descriptions are already configured.
3. Build and run on an iPhone. Add a drink in **Drinks**, then tap it to review its nutrition and log time.
4. Choose Health permissions when requested. Logging requires write access for every known nutrient in that drink; a denied field fails the entire event without saving a partial drink.

In Debug builds, **Settings → Development → Add Development Example Drinks** inserts the seven supplied presets once. Unknown nutrition stays blank. Presets are never inserted automatically in a normal launch and are compiled out of Release builds.

## Data and privacy

Reusable templates live only in this device’s SwiftData store. Actual consumption is saved as independent HealthKit samples and queried from Apple Health. Editing or deleting a template never changes historical samples.

Today’s totals and history show **visible Apple Health nutrition from all sources**, including other apps and foods. They are not presented as drinks-only totals. Empty results cannot establish whether read permission was denied. Limited-history access is respected. Pull to refresh, or return to Tally after changing data or permissions in Health.

The default 400 mg caffeine target is a personal tracking preference, not a medical recommendation. Change it in Settings.

Tally contains no networking, backend, accounts, ads, analytics, or cloud template syncing. Apple Health’s own system-managed sync and backup settings are controlled separately by the user. A JSON export is an explicit user-directed Files action and contains templates only, excluding consumption dates, usage counts, and Health history. Imports add missing UUIDs and keep existing templates unchanged.

See [the data and architecture notes](docs/DATA_AND_ARCHITECTURE.md) for event grouping, save boundaries, and the JSON contract, and [local verification](docs/VERIFICATION.md) for commands and manual Health checks.

## Development

Swift 6, SwiftUI, SwiftData, HealthKit, and Swift Charts. Apple frameworks only; there are no third-party package dependencies.

Run all verification locally with isolated DerivedData under `/private/tmp`. No GitHub Actions workflow is configured. UI tests use an in-memory library and a synthetic Health adapter, never the real Health store.
