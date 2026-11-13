# Local verification

Verification took place on Kai’s Mac on 13 November 2026. No GitHub-hosted Actions were triggered or used. Build products, logs, result bundles, SDK probes, and the isolated QA Simulator are task-local artifacts and are removed after the recorded checks. The two README screenshots are intentional documentation assets and contain synthetic data only.

## Environment

- Xcode 27.0, build 27A266a; Apple Swift 6.4.
- Installed SDK: iPhoneOS 27.0 and iPhoneSimulator 27.0.
- Deployment target: iOS 27.0.
- Physical target: Kai’s iPhone 17 Pro Max, iOS 27.2.
- Final Simulator target: an isolated iPhone 17 Pro Max running iOS 27.0, named `Tally QA`.

`xcodebuild -version`, `xcodebuild -showsdks`, and `xcrun devicectl list devices` were run locally. The final QA Simulator identifier in the commands below is temporary; substitute a currently available destination when rerunning after cleanup.

## SDK verification before implementation

The installed HealthKit headers were inspected for all eight dietary identifiers, units, metadata keys, authorization behavior, array-save atomicity, and limited-read history. A temporary Swift probe successfully typechecked these actual Swift imports and the async APIs before app implementation:

```sh
xcrun --sdk iphoneos swiftc -typecheck -target arm64-apple-ios27.0 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk -module-cache-path /private/tmp/tally-module-cache /private/tmp/tally-sdk-check.swift
```

The probe was not executed and did not write Health data. Its temporary source is removed after verification. `HealthKitStore.swift` and the conversion tests retain the implemented mappings.

## Recorded results

- Combined suite: **37 passed, 0 failed, 0 skipped** (28 unit tests and 9 UI tests).
- Final editor follow-up after the keyboard correction: **2 passed, 0 failed, 0 runtime warnings**.
- Refreshed signed Debug and Release builds: **succeeded**.
- Final physical iPhone installation and launch: **succeeded**.
- The signed app has its HealthKit entitlement and no iCloud entitlements. Debug fixture markers were checked and are absent from the Release binary.

The Xcode commands below are the executed verification arguments; temporary console-log redirection is omitted.

## Standalone unit tests

The final standalone unit run passed all 28 tests:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=2C35846D-BDD6-4946-99C1-11EFC64900CA' -derivedDataPath /private/tmp/tally-derived-data -parallel-testing-enabled NO -only-testing:TallyTests test CODE_SIGNING_ALLOWED=NO
```

## Combined test command

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=2C35846D-BDD6-4946-99C1-11EFC64900CA' -derivedDataPath /private/tmp/tally-derived-data -resultBundlePath /private/tmp/tally-final-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 test CODE_SIGNING_ALLOWED=NO
```

The combined suite passed, but recorded two editor keyboard-layout warnings. The custom keyboard accessory was then removed in favour of native interactive dismissal. Both affected input flows were rerun with the command below; the result bundle reported no runtime warnings, and their focused-field screenshots were opened and inspected.

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=2C35846D-BDD6-4946-99C1-11EFC64900CA' -derivedDataPath /private/tmp/tally-derived-data -resultBundlePath /private/tmp/tally-keyboard-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyUITests/TallyUITests/testConfirmedLogSurvivesTemplateEditAndDeletion -only-testing:TallyUITests/TallyUITests/testCreateTemplateWithUnknownNutritionAndSearch test CODE_SIGNING_ALLOWED=NO
```

## Signed builds

These commands were run locally, using isolated DerivedData:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-device-derived-data -allowProvisioningUpdates build
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-device-derived-data -allowProvisioningUpdates build
```

Both Debug and Release builds succeeded. Release excludes development presets, synthetic Health adapters, and test-only appearance overrides.

## Physical iPhone

The final signed Debug build was installed and launched successfully. Set `TALLY_DEVICE_ID` to the connected iPhone identifier from `xcrun devicectl list devices`; its private value is intentionally excluded from this repository. The actual install and launch commands used that variable:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-device-derived-data/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 15 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```

Earlier foundation launches were blocked by the locked device. Once the iPhone was unlocked, subsequent feature checkpoints and the final build installed and launched successfully. Installation and launch do not establish that real Health writes, permission decisions, or haptics have been manually verified.

## Test and visual scope

Unit coverage includes optional-versus-zero semantics, estimates, numeric validation, draft isolation, real temporary SQLite persistence across containers, usage counts, duplication/deletion, ordering, exact debug preset values, nutrition unit conversion, shared timestamps, metadata, source-aware grouping, half-open calendar ranges, daylight-saving boundaries, missing chart days, date validation, failed saves/queries, and validated JSON transfer including longer valid template text.

UI tests inject an in-memory library and synthetic Health store. They cover creating a blank-nutrition template, search, confirmed logging, editing/deleting a template without changing its existing log, Quick Add with an optional template, denied writes, unavailable Health, query failures, all four tabs, and separate light/dark/accessibility appearance cases. No automated test reads or writes the real Health store.

Screenshots were exported with `xcrun xcresulttool export attachments --path <result-bundle> --output-path <temporary-output>` and opened independently. Today, quick-log cards, the weekly chart, the library, confirmation, the editor, history, and Settings were visually inspected. Accessibility size 3 was checked on Today and the library. The screenshot-confirmed dark-card contrast issue was corrected using semantic secondary grouped surfaces, then both appearances were recaptured and opened again.

Some initial UI attempts exposed test-harness assumptions about text selection, combined accessibility labels, and switch hit areas; those tests were corrected without bypassing the actual controls. Xcode also stalled while relaunching apps within an appearance test. An isolated Simulator and separate appearance cases allowed those checks to complete. Initial interrupted runs were not treated as successful verification.

Xcode’s App Intents metadata tool reports that extraction is skipped because the core app has no App Intents dependency. The initial editor keyboard-layout diagnostics were resolved and rechecked as described above. Spoken VoiceOver order was not manually verified.

## Manual Health checks still required

On the physical iPhone:

1. Review the actual Health permission sheet. Check denial and partial write access, then adjust choices in Health’s profile → Apps → Tally.
2. Log a drink and inspect its exact nutrient amounts, shared timestamp, estimate metadata where available, and source in Apple Health. Verify only known values were written.
3. Edit and log the template again; confirm the earlier Health entry is unchanged. Delete the template and confirm its Health history remains.
4. Compare visible totals with the underlying Health entries, including nutrition from other apps, backdated entries, denied reads, and limited-history windows.
5. Check success haptics, spoken VoiceOver navigation, and the system Files export/import pickers on-device.

These live checks remain distinct from compilation, synthetic UI tests, and successful physical installation/launch.
