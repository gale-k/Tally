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
