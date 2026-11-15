# Sodium and salt verification — 15 November 2026

All builds and tests run locally on Kai’s Mac with Xcode 27.0. DerivedData and result bundles are isolated under `/private/tmp/tally-sodium-20261115`. GitHub Actions are not used.

## Behaviour

- Saved-item editing and Quick Add offer sodium (mg) or salt (g) under **More Nutrition**.
- Switching input representation converts the existing amount. The food-label conversion is 1 g salt = 400 mg sodium; only sodium is stored and logged to Health.
- Blank stays unknown, explicit zero stays loggable, and the estimate marker follows the value.
- Optional sodium survives local persistence, duplication, snapshot import/restore, and CloudKit record encoding/merging. Older stores and snapshots open with unknown sodium.
- **Settings → Nutrition on Today → Show Sodium** enables an optional sodium summary; it starts off.
- Logging an undecided newly supported Health write type requests authorization again. Explicit denials do not cause repeated prompts or partial event saves.

## Local commands and results

The commands below were run from the repository root. Build/test output was redirected into task-specific `.log` files beside the result bundles. The QA simulator is an isolated iPhone 17 Pro Max running iOS 27.0; its identifier is temporary.

### Initial unit and performance suite

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/unit-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests test CODE_SIGNING_ALLOWED=NO
```

Succeeded: 68 passed, one opt-in live CloudKit test skipped, zero failures. This includes the existing snapshot-decoding performance test and six initial sodium tests. Two further sodium regressions cover readable unit-conversion precision and an existing authorization denial.

### Full UI suite

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/ui-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:TallyUITests test CODE_SIGNING_ALLOWED=NO
```

Succeeded: all 18 UI tests passed, zero failures. This run covers sodium/salt entry, unit switching, estimates, saved-template reopening, historical logging, and a sodium-only Today card, plus existing food/caffeine logging, template changes, error states, cloud settings, appearance, accessibility descriptions, and serving amount controls. It preceded the final small conversion-precision adjustment and the additional sodium accessibility-size test; the focused final run below verifies those changes.

### Final unit, performance, and sodium UI checks

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/verification-tests.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltCanBeSavedConvertedAndLogged -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltWithLargeText -only-testing:TallyUITests/TallyUITests/testQuickAddSodiumCanAppearOnToday test CODE_SIGNING_ALLOWED=NO
```

Succeeded: 70 unit/performance tests passed, one opt-in live CloudKit test skipped, and all three selected UI tests passed. Zero failures. All eight sodium unit tests passed. Standard editor, dark accessibility-size editor, sodium history, and sodium-only Today captures were exported and visually inspected. The accessibility-size editor's salt label, numeric value, unit, estimate toggle, and unit picker were readable and operable.

Earlier focused runs exposed a UI-test helper defect: XCTest considered a partly visible **More Nutrition** row hittable while its tap point was behind the keyboard, so the disclosure never opened. A longer scrolling allowance alone did not resolve it. A recording and temporary UI hierarchy dump identified the obscured tap. The helper now reveals the control's centre between the navigation bar and keyboard and can scroll back to an earlier control. The temporary dump was removed; app code did not require a change for this failure.

The first failed run's automatic diagnostic collection then stalled after its tests ended. That collector was interrupted and terminated; its result bundle remained incomplete. Subsequent runs use `-collect-test-diagnostics never`, and both failures and the final success completed normally. These were the earlier failed commands:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/final-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:TallyTests -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltCanBeSavedConvertedAndLogged -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltWithLargeText -only-testing:TallyUITests/TallyUITests/testQuickAddSodiumCanAppearOnToday test CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/large-text-retry.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltWithLargeText test CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=BEC03B58-32C3-4B20-BE47-B3583FB92C52' -derivedDataPath /private/tmp/tally-sodium-20261115/simulator -resultBundlePath /private/tmp/tally-sodium-20261115/large-text-diagnosis.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never -only-testing:TallyUITests/TallyUITests/testSodiumAndSaltWithLargeText test CODE_SIGNING_ALLOWED=NO
```

The first command's unit suite and two standard UI cases passed before its large-text failure; the collector ultimately exited 143 when terminated. The two isolated retries exited 65 for the same obscured disclosure tap. The successful final command above verifies the corrected helper.

### Signed iPhone build

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-sodium-20261115/device -allowProvisioningUpdates build
```

Succeeded, including the final unit-conversion formatting. The build was repeated after the final app changes; no further changes to the sodium implementation followed the successful device installation below. Separate concurrent app changes are scoped out in the final review note.

### Physical iPhone

The connected device identifier is intentionally omitted; `TALLY_DEVICE_ID` represents the actual identifier passed to these commands.

```sh
xcrun devicectl --timeout 60 device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-sodium-20261115/device/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 20 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```

Both succeeded. The first install attempt failed with a CoreDevice connection reset; a later lock-state query responded successfully and the retry installed and launched Tally. The initial sandboxed device listing also timed out; the required local device and Simulator checks used the approved service access.

## Final review and cleanup

`git diff --check` passed. The README and architecture notes were updated. Work stays uncommitted on the existing `test/live-icloud-verification` branch; no push, branch creation, or hosted testing occurred. The pre-existing Xcode project-file changes were preserved. Separate Daily Intake files and changes to the dashboard, Settings, summary cards, and Health refresh appeared during final cleanup, after the verified sodium binaries were compiled and installed. Those edits were preserved. The commands and captures above verify the sodium build before that concurrent work; this task did not rebuild or install the later shared working-tree state.

The task-specific QA simulator, DerivedData, result bundles, logs, extracted screenshots/recording frames, and Swift probe cache were removed after inspection. Commands above document their former paths; they are not retained artifacts.

## Verification limits

UI tests use an in-memory library and a synthetic Health adapter. Real Health sample writes, the system sodium permission sheet, spoken VoiceOver, and live two-device iCloud convergence were not verified. Sodium HealthKit sample type, mg-to-g conversion, event metadata, and estimate flags are checked through real `HKQuantitySample` construction without writing to personal Health data. CloudKit record conversion and merges run locally without contacting iCloud.
