# Tally

A native iPhone nutrition utility for saving your usual foods and drinks and logging their known nutrition to Apple Health.

## What it does

- Save reusable foods and drinks with favourites, brands, serving sizes, notes, and optional nutrition.
- Find a saved item with search, category filters, five sort orders, and ranked Quick Log cards.
- Review an item and its time before logging, or use Quick Add for a one-off entry.
- Choose calorie, protein, sugar, and caffeine summaries on Today, with recent Health history and an optional seven-day caffeine chart.
- Optionally sync saved templates through your private iCloud storage, with offline edits and explicit account-switch control.
- Export independent JSON snapshots to Files/iCloud Drive; import missing items or restore older snapshots as new copies.

Supported nutrition: caffeine (mg), energy (kcal), sugar, carbohydrates, protein, total fat, saturated fat, and fibre (g). **Blank means unknown; zero is a real value.** Tap `~` beside a nutrition field to mark it as estimated.

## Preview

Local Simulator screenshots with synthetic test data, not personal Health history.

| Light | Dark |
| --- | --- |
| <img src="docs/images/today-light.png" width="260" alt="Tally Today in light mode"> | <img src="docs/images/today-dark.png" width="260" alt="Tally Today in dark mode"> |

## Getting started

1. Open `Tally.xcodeproj` in Xcode 27.0 or later. The project uses the installed iOS 27 SDK and requires iOS 27.0 or later.
2. Select your Apple development team. HealthKit, iCloud/CloudKit, Push Notifications, remote-notification background mode, and Health purpose descriptions are configured. Create/select `iCloud.gale-k.Tally` in Signing & Capabilities and regenerate provisioning for these capabilities. See [iCloud setup](docs/ICLOUD_SYNC.md#developer-setup).
3. Build and run on an iPhone. Add a food or drink in **Library**, then tap it to review its nutrition and log time.
4. Choose Health permissions when requested. Logging requires write access for every known nutrient in that entry; a denied field fails the entire event without saving partial nutrition.

In Debug builds, **Settings → Development → Add Development Examples** inserts six synthetic food and drink templates once. These are demonstration values, not a nutrition reference. The original once-only marker is retained, so users who previously added examples do not receive another batch. Unknown nutrition stays blank. Presets are never inserted automatically in a normal launch and are compiled out of Release builds.

## Food and drink templates

A name is the only required template field. Serving size is free text (for example, “1 bowl” or “330 ml”); liquid volume and serving style are optional. New items start with no specified style. Food categories sit alongside the existing coffee, tea, pod, and bottled-drink options.

Calories, protein, sugar, and caffeine are immediately accessible in the editor. Carbohydrates, fats, and fibre are under **More Nutrition**. Cards show the known values that best describe each item, so a protein-only food never needs a caffeine placeholder. Configure the Today cards in **Settings → Nutrition on Today**. Hiding caffeine also hides its weekly chart; the personal tracking target remains available in Settings.

Existing libraries and version-1 JSON exports continue to work. The internal `SavedDrink` type and the JSON `drinks` key retain their original names to preserve compatibility; exported files are now named **Tally Library**. Existing logged drink names and Apple Health metadata remain unchanged.

## Data and privacy

Reusable food and drink templates remain available in this device’s SwiftData store. Optional iCloud sync sends template details, including nutrition, notes, and favourites, to your private CloudKit database after confirmation in Settings. Actual consumption is saved as independent HealthKit samples and queried from Apple Health. Editing or deleting a template never changes historical samples.

Today’s totals and history show **visible Apple Health nutrition from all sources**, including other apps and foods. They are not presented as drinks-only totals. Empty results cannot establish whether read permission was denied. Limited-history access is respected. Pull to refresh, or return to Tally after changing data or permissions in Health.

The default 400 mg caffeine target is a personal tracking preference, not a medical recommendation. Change it in Settings.

Tally has no custom backend, Tally account, ads, or analytics. The only app-managed network transfer is optional template sync through Apple CloudKit. Preferences, convenience usage counts/dates, and Health permission state stay local. Apple Health’s own system-managed sync and backup settings are controlled separately by the user.

Live sync propagates edits and deletions; it is not an independent backup. **Settings → Backups & Restore → Export Library Snapshot** creates a manual version-1 JSON snapshot. Choose iCloud Drive in Files to keep a recovery copy there. Imports add missing UUIDs and keep existing templates unchanged. **Restore Snapshot as New Copies** creates fresh identities after confirmation, allowing recovery of older versions without overwriting current templates. These actions exclude consumption dates, usage counts, and Health history. See [iCloud sync and recovery](docs/ICLOUD_SYNC.md) for conflicts, account changes, and recovery steps.

See [the data and architecture notes](docs/DATA_AND_ARCHITECTURE.md) for event grouping, save boundaries, and the JSON contract, and [local verification](docs/VERIFICATION.md) for the initial app checks. The [general nutrition verification](docs/ISSUE_2_VERIFICATION.md) records the theme-change checks. [iCloud verification](docs/ISSUE_1_VERIFICATION.md) records the current local tests, successful signed iPhone installation and launch, and the later [live CloudKit and iCloud Drive checks](docs/LIVE_ICLOUD_VERIFICATION.md), including their remaining device/UI limits.

## Development

Swift 6, SwiftUI, SwiftData, CloudKit (`CKSyncEngine`), HealthKit, and Swift Charts. Apple frameworks only; there are no third-party package dependencies.

Run all verification locally with isolated DerivedData under `/private/tmp`. No GitHub Actions workflow is configured. UI tests use an in-memory library, a synthetic Health adapter, and disabled CloudKit access; they never contact the real Health store or iCloud.

Optional live verification uses uniquely owned Development CloudKit scratch resources and a synthetic iCloud Drive snapshot. It is explicitly gated and skipped by ordinary tests; see [live verification](docs/LIVE_ICLOUD_VERIFICATION.md) before running the helpers.

The neutral plate-and-tally icon has reproducible native drawing source in [Design/RenderAppIcon.swift](Design/RenderAppIcon.swift).
