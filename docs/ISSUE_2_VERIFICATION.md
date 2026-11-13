# General nutrition theme verification — issue #2

All verification ran locally on Kai’s Mac on 13 November 2026. No GitHub-hosted Actions were triggered or used. Xcode 27.0 (27A266a), the installed iOS 27 SDK, and the existing iOS 27 deployment target were retained.

## Scope and compatibility

The app now uses a neutral plate-and-tally icon, adaptive teal accent, a Library for foods and drinks, balanced nutrition summaries, optional serving details, and app-wide food-and-drink wording. Calories, protein, sugar, and caffeine can be shown independently on Today; the caffeine chart follows its visibility setting.

The `SavedDrink` class, UUID constraint, persisted property names/types, existing category/style raw values, HealthKit metadata keys, and JSON version-1 `drinks` key are unchanged. New food category values are additive. A fixed legacy JSON document, food-category round trips, SwiftData persistence, nil/zero/estimate semantics, historical event grouping, and the original seed marker have regression coverage. No Health sample is migrated or rewritten.

Runtime checking found a deletion bug: the confirmation’s dismissal could clear the selected template before the delete action used it. The action now captures the presented template. The confirmed-log/edit/delete UI test verifies that the template disappears while its original 100 mg Health event remains unchanged.

## Results

- Final combined suite: **47 passed, 0 failed, 0 skipped** (35 unit tests and 12 UI tests), with **0 runtime warnings** in the result summary.
- Signed Debug build: succeeded; the final app installed and launched on the physical iPhone 17 Pro Max.
- Signed Release build: succeeded. Code signature verification succeeded with normal macOS trust-store access; the HealthKit entitlement is present. Development fixture/seed markers are absent from the Release executable.
- The icon renderer produced a 1024 × 1024 opaque PNG. Its native drawing source is retained in `Design/RenderAppIcon.swift`.

## Exact final commands

Console-log redirection is omitted. Every relevant Xcode invocation used isolated DerivedData under `/private/tmp`. The QA Simulator identifier below is task-specific; select a current destination when rerunning after cleanup.

Initial Simulator compile — succeeded:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tally-issue2-derived-data build CODE_SIGNING_ALLOWED=NO
```

Final complete suite on the isolated iPhone 17 Pro Max / iOS 27.0 Simulator:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=C97666B8-AF04-43C8-A814-B985C11F27F0' -derivedDataPath /private/tmp/tally-issue2-derived-data -resultBundlePath /private/tmp/tally-issue2-complete-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 test CODE_SIGNING_ALLOWED=NO
```

Signed builds — both succeeded:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue2-device-derived-data -allowProvisioningUpdates build
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue2-device-derived-data -allowProvisioningUpdates build
```

Physical installation and launch — both succeeded. `TALLY_DEVICE_ID` stands for the connected iPhone identifier; the private value is deliberately excluded here:

```sh
xcrun devicectl device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-issue2-device-derived-data/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 20 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
```

Production configuration and artwork checks:

```sh
codesign -d --entitlements - --xml /private/tmp/tally-issue2-device-derived-data/Build/Products/Release-iphoneos/Tally.app
codesign --verify --strict --verbose=2 /private/tmp/tally-issue2-device-derived-data/Build/Products/Release-iphoneos/Tally.app
plutil -extract NSHealthShareUsageDescription raw -o - /private/tmp/tally-issue2-device-derived-data/Build/Products/Release-iphoneos/Tally.app/Info.plist
plutil -extract NSHealthUpdateUsageDescription raw -o - /private/tmp/tally-issue2-device-derived-data/Build/Products/Release-iphoneos/Tally.app/Info.plist
swift -module-cache-path /private/tmp/tally-issue2-module-cache Design/RenderAppIcon.swift
sips -g pixelWidth -g pixelHeight -g hasAlpha Tally/Assets.xcassets/AppIcon.appiconset/AppIcon.png
git diff --check
```

The signing inspection initially produced trust/entitlement warnings inside the restricted shell. Repeating it with normal local trust-store access returned valid signing and the expected HealthKit entitlement; no signing configuration was changed to suppress a warning.

## Development failures and diagnostic limits

The first test destination was the stock iPhone 17 Pro Max running iOS 26.5; Xcode correctly rejected it (exit 70). A separate iOS 27.0 Simulator was then created rather than lowering the app’s deployment target.

Earlier combined runs used the complete-suite command above with result paths `tally-issue2-full-tests.xcresult` and `tally-issue2-final-tests.xcresult`. They exposed the deletion-selection problem, overscrolled lazy-form fields, an unreliable Simulator Command-A interaction, and an assertion that overlooked SwiftUI’s combined accessibility label. The app defect was fixed; test interactions now scroll to the actual target and replace text through the native decimal keyboard. A `tally-issue2-reviewed-tests.xcresult` attempt stopped at a confirmation-closure syntax error, which was corrected before tests continued. These runs are not reported as successful.

A focused diagnostic command ran the three affected cases:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=C97666B8-AF04-43C8-A814-B985C11F27F0' -derivedDataPath /private/tmp/tally-issue2-derived-data -resultBundlePath /private/tmp/tally-issue2-focused-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyUITests/TallyUITests/testAccessibilityDescriptionsAndTextClipping -only-testing:TallyUITests/TallyUITests/testConfirmedLogSurvivesTemplateEditAndDeletion -only-testing:TallyUITests/TallyUITests/testFoodWithCaloriesAndProteinCanBeSavedAndLogged test CODE_SIGNING_ALLOWED=NO
```

The food and historical edit/delete cases passed. The broad accessibility audit failed: it reported non-scaling text that visibly enlarges in the explicit accessibility-size captures, native navigation/control findings, and contrast findings on off-screen text beneath the translucent tab bar. That broad audit was diagnostic, not a passed compliance check. The persistent automated audit now checks sufficient element descriptions on Today, Library, History, Settings, confirmation, and the editor. Actual large-text layouts and both appearances are reviewed separately. The screenshot-confirmed filled-button contrast and date-text contrast were improved. No claim of a clean blanket contrast/Dynamic Type audit or manually verified spoken VoiceOver is made.

## Actual system Dynamic Type follow-up

The initial view-level large-text fixture enlarged the tabs but did not carry its override into modal sheets. Those initial modal captures were rejected as accessibility-size evidence. The isolated Simulator’s system category was set explicitly, exposing an awkward wrap in the optional volume row. Volume and nutrition fields now stack label/input vertically at accessibility sizes. The corrected editor, nutrition inputs, confirmation, and Quick Add action were recaptured and opened; the label and controls are readable without the earlier fragmented wrap. The Debug-only modal fixture now applies its appearance environment at the modal root as well, so future screenshot tests cover the intended size.

Both system-size follow-ups passed, one UI test each. The first run used `tally-issue2-system-text-tests.xcresult`; after the layout correction, the exact command was:

```sh
xcrun simctl ui C97666B8-AF04-43C8-A814-B985C11F27F0 content_size accessibility-extra-large
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=C97666B8-AF04-43C8-A814-B985C11F27F0' -derivedDataPath /private/tmp/tally-issue2-derived-data -resultBundlePath /private/tmp/tally-issue2-accessibility-layout-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyUITests/TallyUITests/testScreenshotsAccessibilityText test CODE_SIGNING_ALLOWED=NO
xcrun simctl ui C97666B8-AF04-43C8-A814-B985C11F27F0 content_size large
```

The full suite and signed Debug/Release builds were then repeated on the final source. The corrected Debug app was installed and launched again on the physical iPhone.

## Runtime screenshots and remaining manual checks

UI tests use an in-memory library and synthetic Health adapter, never real Health samples. Their screenshots cover Today, Library, History, Settings, confirmation, Add Item, Quick Add, food-only history details, empty Today, and permission/query/unavailable states. Light, dark, and accessibility-size-3 captures are exported from the actual test run and opened independently. The two refreshed README screenshots contain synthetic data only.

Full Health permission decisions, exact live sample counts/values in Apple Health, haptic feel, and spoken VoiceOver navigation remain physical-device manual checks. Installation and launch succeeded but do not establish those behaviours. No performance test target exists in the repository; no standalone performance benchmark was claimed. iCloud sync is outside this issue and remains separate work.

Task-specific DerivedData, logs, result bundles, exported diagnostic attachments, module cache, and the isolated QA Simulator are removed after verification. The icon source and README images are intentional project/documentation assets.
