# Daily Intake verification

Verified locally on Kai’s Mac on 15 November 2026. No GitHub-hosted Actions were triggered or used. All Xcode work used isolated DerivedData under `/private/tmp/tally-issue-6`. The task-owned iPhone 17 Pro Max simulator runs iOS 27.0. Health UI tests use synthetic data, an in-memory library, and prohibited CloudKit access.

## Results

Final combined run: **87 passed, 0 failed, 1 skipped** (77 passing unit tests, 10 passing UI tests, and the opt-in live CloudKit test skipped). The result bundle reports **no runtime warnings** and one test with performance metrics.

- Final signed Debug build: succeeded.
- Final signed Release build: succeeded. A binary check confirmed the UI-test preference flags are absent.
- Final physical iPhone installation: succeeded.
- Final physical iPhone launch: succeeded.
- `git diff --check`: succeeded.

## Exact build and test commands

Commands ran from the repository root. Temporary console-log redirection is omitted. Both device builds below succeeded after the final accessibility-label correction:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue-6/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue-6/device build
```

The initial standalone simulator build also succeeded:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tally-issue-6/simulator build CODE_SIGNING_ALLOWED=NO
```

The final combined unit/UI verification command was:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination "platform=iOS Simulator,id=D7AE428B-D846-4DC2-8B93-C3568CE143E0" -derivedDataPath /private/tmp/tally-issue-6/simulator -resultBundlePath /private/tmp/tally-issue-6/verified.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180 "-only-testing:TallyTests" "-only-testing:TallyUITests/TallyUITests/testDailyIntakeSettingsPersistAndUpdateToday" "-only-testing:TallyUITests/TallyUITests/testDailyIntakePreservesLegacyCaffeineAndVisibility" "-only-testing:TallyUITests/TallyUITests/testDailyIntakeKnownZeroStillCompares" "-only-testing:TallyUITests/TallyUITests/testDailyIntakeDarkLargeTextAndAccessibility" "-only-testing:TallyUITests/TallyUITests/testDailyIntakeUnknownAndFailedHealthData" "-only-testing:TallyUITests/TallyUITests/testTodayNutrientsCanBeConfiguredWithoutChangingTemplates" "-only-testing:TallyUITests/TallyUITests/testQuickAddSodiumCanAppearOnToday" "-only-testing:TallyUITests/TallyUITests/testScreenshotsLight" "-only-testing:TallyUITests/TallyUITests/testScreenshotsDark" "-only-testing:TallyUITests/TallyUITests/testAccessibilityDescriptions" test CODE_SIGNING_ALLOWED=NO
```

The selected unit suite includes the existing `testSnapshotDecodePerformance` measurement. The live CloudKit test remains opt-in and was skipped; daily preference changes have no CloudKit path.

## Physical iPhone

`xcrun devicectl list devices` identified the connected physical iPhone. Its private identifier is represented below by `TALLY_DEVICE_ID`; the executed install/launch commands substituted that actual identifier. Both commands succeeded on the final corrected Debug build:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-issue-6/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```

Installation and launch are separate from manually comparing real Apple Health totals or listening to spoken VoiceOver output.

## Coverage and regression checks

Seven new unit tests cover all eight defaults and meanings; persisted values and enable flags using the real AppStorage keys; legacy caffeine/visibility preservation; strict locale-aware input validation; absent versus explicit zero; below/at/above targets and uncapped percentages; finite arithmetic; protein/fibre wording; same-day failed refreshes; new-day clearing and recovery; all-source estimates; and autumn daylight-saving boundaries. Existing coverage includes spring daylight-saving and template/JSON/sync compatibility.

Five new UI flows exercise actual Settings and Today controls: editing, immediate progress updates, invalid zero rejection without overwriting the saved amount, disable/relaunch/reset, preservation of legacy caffeine and visibility preferences, exactly-at/over-target states, a real logged zero, missing/failed Health reads, all eight settings rows, dark appearance, and accessibility text size 3. Accessibility-description audits run on the new breakdown and editor as well as existing main screens.

The affected regression checks cover the existing sodium-only Today card and its accessible zero amount, independent dashboard visibility, unchanged template nutrition, and light/dark navigation through Today, Library, confirmation, editor, Quick Add, History, and Settings. The implementation does not modify template models, nutrition values, export/sync payloads, Health sample creation, or authorization rules. Pre-existing sodium/project/test work was preserved.

## Screenshots

Opened and inspected the final saved captures for Today in light/dark appearance, the full daily breakdown, an above-target comparison, validation with the keyboard visible, failed Health data, the preserved sodium-only card, Settings, and the daily settings/editor at accessibility size 3. The scrolled large-text capture shows a complete protein card with its amount, reference, bar, percentage, difference, and all-source caption inside the viewport. No concrete visual problems were found in these inspected states.

The verified Today light/dark captures replace `docs/images/today-light.png` and `today-dark.png` in the README. Zero/unknown and persistence assertions also passed through the real UI; the known-zero screenshot was captured during a tab transition and is not relied upon as visual proof.

Runtime captures are exported with:

```sh
xcrun xcresulttool export attachments --path /private/tmp/tally-issue-6/verified.xcresult --output-path /private/tmp/tally-issue-6/screens-final
```

## Earlier attempts and remaining limits

An initial destination disappeared before tests started, so a task-owned simulator was created. Two initial UI failures came from the shared text-field helper assuming the old placeholder; it now checks the actual placeholder. An affected regression test then detected an unintended change to the sodium amount’s accessibility label; that label was restored and the corrected build rerun. Xcode stalled while closing that failed run after all selected tests had ended, so only that task’s runner was terminated. These attempts are not counted as successful final verification.

The normal App Intents extraction warning reports no AppIntents framework dependency. No App Intents are part of this feature.

Spoken VoiceOver, live changes to real Health permissions/data, a system-clock change while the app stays foregrounded, and a physical midnight rollover were not manually exercised. The underlying day-window/DST and error transitions have local unit coverage. The physical app is installed and launched for those manual checks. Task-owned build products, result bundles, logs, screenshots, baseline copies, and the temporary simulator are removed after inspection; intentional README preview images remain in the repository.

## Sodium maximum follow-up — 16 November 2026

Added a device-local sodium comparison, starting at 2,400 mg (6 g salt), with a salt/sodium input selector and tracking-maximum wording. The original verification above remains a historical record.

The final signed Debug build succeeded; 78 unit tests and 3 UI tests passed, with one opt-in live CloudKit test skipped. The existing snapshot decode performance test was included. The UI tests covered salt input and sodium progress, existing daily-intake settings, and large-text accessibility descriptions. The signed build was installed and launched on the physical iPhone. Spoken VoiceOver and real Health data were not manually checked.

Exact local build and test commands (console log redirection omitted; the simulator is task-owned and removed afterwards):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-sodium-max-device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=0E11073E-858E-407B-AE96-484917A4450A' -derivedDataPath /private/tmp/tally-sodium-max-sim -resultBundlePath /private/tmp/tally-sodium-max-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testSodiumDailyMaximumCanBeEditedAsSalt -only-testing:TallyUITests/TallyUITests/testDailyIntakeSettingsPersistAndUpdateToday -only-testing:TallyUITests/TallyUITests/testDailyIntakeDarkLargeTextAndAccessibility test CODE_SIGNING_ALLOWED=NO
```

For the physical device, the private device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-sodium-max-device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```


## Calories layout follow-up — 16 November 2026

The Today calories card spans the nutrition grid width, while the other cards retain their adaptive layout. The signed Debug build passed; 78 unit tests and 4 UI tests passed, with one opt-in live CloudKit test skipped. The performance measurement was included. Inspected the running iPhone 17 Pro Max simulator in light appearance at standard and accessibility text sizes. Installed and launched the signed build on the physical iPhone.

Exact local commands (console-log redirection omitted):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-calorie-layout/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=736A1DDE-C907-466B-9A19-7D4E7A59D90C' -derivedDataPath /private/tmp/tally-calorie-layout/simulator -resultBundlePath /private/tmp/tally-calorie-layout/tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testScreenshotsLight -only-testing:TallyUITests/TallyUITests/testScreenshotsAccessibilityText -only-testing:TallyUITests/TallyUITests/testTodayNutrientsCanBeConfiguredWithoutChangingTemplates -only-testing:TallyUITests/TallyUITests/testQuickAddSodiumCanAppearOnToday test CODE_SIGNING_ALLOWED=NO
```

The device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-calorie-layout/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```


## Nutrition card alignment follow-up — 16 November 2026

Today’s smaller nutrition cards expand to the same height within each grid row. The repeated all-sources caption was removed from individual cards; the source and read-access explanation remains available once on Today and at the top of Daily Intake. The signed Debug build passed. The local run passed 78 unit tests and six UI tests, with one opt-in live CloudKit test skipped and no recorded runtime warnings. Inspected simulator screenshots in light, dark, accessibility text size 3, and with sodium enabled; the rows align and the breakdown retains the source note. The signed build installed and launched on the physical iPhone.

Exact local commands (console-log redirection omitted; the task-owned simulator was removed after testing):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-card-alignment/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=AAFA4DB4-3AC2-4EAF-B9AE-EC594F8A4C8A' -derivedDataPath /private/tmp/tally-card-alignment/simulator -resultBundlePath /private/tmp/tally-card-alignment/tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testNutritionCardRowsAndSourceNote -only-testing:TallyUITests/TallyUITests/testScreenshotsLight -only-testing:TallyUITests/TallyUITests/testScreenshotsDark -only-testing:TallyUITests/TallyUITests/testScreenshotsAccessibilityText -only-testing:TallyUITests/TallyUITests/testTodayNutrientsCanBeConfiguredWithoutChangingTemplates -only-testing:TallyUITests/TallyUITests/testSodiumDailyMaximumCanBeEditedAsSalt test CODE_SIGNING_ALLOWED=NO
```

The physical device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-card-alignment/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```


## Nutrition bar alignment follow-up — 16 November 2026

Each available progress bar sits immediately below its nutrient amount, keeping bars aligned when reference labels or salt equivalents wrap. Unknown data still has no fabricated progress. The signed Debug build passed; 78 unit tests and six UI tests passed, with one opt-in live CloudKit test skipped and no recorded runtime warnings. Visually inspected light and dark simulator captures, including four populated smaller cards and an accessibility text-size view. Installed and launched the signed app on the physical iPhone.

Exact local commands (console-log redirection omitted; the task-owned simulator was removed after testing):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-nutrition-bars/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=810EDFDF-BA4A-4D50-8DBA-A834900FEEED' -derivedDataPath /private/tmp/tally-nutrition-bars/simulator -resultBundlePath /private/tmp/tally-nutrition-bars/tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testNutritionCardRowsAndSourceNote -only-testing:TallyUITests/TallyUITests/testScreenshotsLight -only-testing:TallyUITests/TallyUITests/testScreenshotsAccessibilityText -only-testing:TallyUITests/TallyUITests/testSodiumDailyMaximumCanBeEditedAsSalt -only-testing:TallyUITests/TallyUITests/testDailyIntakeUnknownAndFailedHealthData -only-testing:TallyUITests/TallyUITests/testAccessibilityDescriptions test CODE_SIGNING_ALLOWED=NO
```

The physical device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-nutrition-bars/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```


## Nutrition text alignment follow-up — 16 November 2026

Reference labels and status lines align across neighbouring cards despite differently wrapped labels and the sodium salt equivalent. Status heights are measured rather than truncated; accessibility-size single-column cards retain their natural spacing. The signed Debug build passed; 78 unit tests and six UI tests passed, with one opt-in live CloudKit test skipped and no recorded runtime warnings. Inspected light and dark simulator captures, including populated sodium and accessibility text size 3. Installed and launched the signed app on the physical iPhone.

Exact local commands (console-log redirection omitted; the task-owned simulator was removed after testing):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-text-alignment/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=ACDAB7FC-5623-4FB3-835F-D7F90C9EBC47' -derivedDataPath /private/tmp/tally-text-alignment/simulator -resultBundlePath /private/tmp/tally-text-alignment/tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testNutritionCardRowsAndSourceNote -only-testing:TallyUITests/TallyUITests/testScreenshotsLight -only-testing:TallyUITests/TallyUITests/testScreenshotsAccessibilityText -only-testing:TallyUITests/TallyUITests/testSodiumDailyMaximumCanBeEditedAsSalt -only-testing:TallyUITests/TallyUITests/testDailyIntakeUnknownAndFailedHealthData -only-testing:TallyUITests/TallyUITests/testAccessibilityDescriptions test CODE_SIGNING_ALLOWED=NO
```

The physical device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-text-alignment/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```


## Daily wording follow-up — 16 November 2026

Card and settings labels now use only “Daily target” or “Daily maximum”, with corresponding target/maximum progress wording. The detailed settings and breakdown explain that the food-label defaults are general tracking comparisons rather than personalised advice or universal safe limits. Existing numeric values and nutrient classifications remain unchanged. The signed Debug build passed; 78 unit tests and five UI tests passed, with one opt-in live CloudKit test skipped and no recorded runtime warnings. Inspected populated dark Today and large-text breakdown screenshots. Installed and launched the signed app on the physical iPhone.

Exact local commands (console-log redirection omitted; the task-owned simulator was removed after testing):

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-daily-wording/device build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=9D76AB12-2F66-4C40-8241-A17472F1337E' -derivedDataPath /private/tmp/tally-daily-wording/simulator -resultBundlePath /private/tmp/tally-daily-wording/tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testNutritionCardRowsAndSourceNote -only-testing:TallyUITests/TallyUITests/testDailyIntakeSettingsPersistAndUpdateToday -only-testing:TallyUITests/TallyUITests/testDailyIntakeDarkLargeTextAndAccessibility -only-testing:TallyUITests/TallyUITests/testSodiumDailyMaximumCanBeEditedAsSalt -only-testing:TallyUITests/TallyUITests/testAccessibilityDescriptions test CODE_SIGNING_ALLOWED=NO
```

The physical device identifier is represented by `TALLY_DEVICE_ID`:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-daily-wording/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```
