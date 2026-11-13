# iCloud library verification — issue #1

Verification ran locally on Kai’s Mac on 13 November 2026, using Xcode 27.0 (27A266a), the installed iOS 27 SDK, and the unchanged iOS 27 deployment target. No GitHub-hosted Actions were triggered or used.

## Implementation and scope

Optional private CloudKit sync uses `CKSyncEngine`, a transactional local template outbox, stable UUIDs, explicit account binding, deterministic whole-template conflict resolution, and durable deletion markers. The existing `SavedDrink` schema/unique UUID and local SwiftData storage remain intact. New local entities contain sync metadata; automatic SwiftData CloudKit integration remains disabled. Preferences, Health permission state, usage counts/dates, and Health history are excluded from the transfer DTO.

Version-1 JSON snapshots remain supported. Ordinary import is additive/idempotent; explicit restore-as-copies recovers older values under fresh UUIDs without overwriting current templates. Files/iCloud Drive selection is user-directed and backups are manual. Setup and recovery are documented in [ICLOUD_SYNC.md](ICLOUD_SYNC.md), and implementation boundaries in [DATA_AND_ARCHITECTURE.md](DATA_AND_ARCHITECTURE.md).

## Results

- Final reviewed complete suite: **67 passed, 0 failed, 0 skipped** (53 unit tests, including the snapshot performance measurement, and 14 UI tests); the result summary contains **0 runtime warnings**.
- Actual system accessibility-size check: **1 UI test passed**. Exported captures of iCloud status, confirmation, and backup actions were opened and visually reviewed. The native confirmation fits at accessibility size 3; controls and wrapped labels remain reachable.
- Generic Debug Simulator compilation: succeeded. The complete suite also rebuilds the Debug app and test targets.
- Final Release iPhone compilation with signing disabled: succeeded. This is a compiler/build check, not a signed or installable-device verification.
- Final signed Debug build: **failed because Xcode reports “No Accounts” and the cached provisioning profile lacks iCloud, Push Notifications, the CloudKit container, and their entitlements**.
- Physical iPhone installation/launch: **not completed for this change**, because no valid signed build can be produced with that profile. The new capabilities were not removed to evade this requirement.
- Live CloudKit exchanges, two-iPhone convergence/offline recovery, real sign-out/account switch/quota errors, and an iCloud Drive round trip: **unverified**. A second eligible device has not been confirmed.

## Exact final commands

Console redirection is omitted. All relevant Xcode commands use isolated DerivedData under `/private/tmp`. The simulator UUID was task-specific and is removed after testing; select a current iOS 27 destination when rerunning.

Initial Simulator build — succeeded:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/tally-issue1-derived-data build CODE_SIGNING_ALLOWED=NO
```

Final reviewed complete unit/performance/UI suite:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=76AC15DD-B86E-4B93-BFD1-E938EFF2BBD5' -derivedDataPath /private/tmp/tally-issue1-derived-data -resultBundlePath /private/tmp/tally-issue1-reviewed-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 test CODE_SIGNING_ALLOWED=NO
```

Final unsigned Release iPhone build — succeeded:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue1-release-derived-data build CODE_SIGNING_ALLOWED=NO
```

Signed Debug build — failed with the account/provisioning errors above, both initially and after the final implementation:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-issue1-device-derived-data -allowProvisioningUpdates build
```

Actual system text-size follow-up — succeeded after correcting the test’s popover dismissal:

```sh
xcrun simctl ui 76AC15DD-B86E-4B93-BFD1-E938EFF2BBD5 content_size accessibility-extra-large
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=76AC15DD-B86E-4B93-BFD1-E938EFF2BBD5' -derivedDataPath /private/tmp/tally-issue1-derived-data -resultBundlePath /private/tmp/tally-issue1-corrected-large-text-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -only-testing:TallyUITests/TallyUITests/testCloudSettingsDarkAndLargeText test CODE_SIGNING_ALLOWED=NO
xcrun simctl ui 76AC15DD-B86E-4B93-BFD1-E938EFF2BBD5 content_size large
```

Configuration/diff inspection — succeeded:

```sh
plutil -lint Tally/Info.plist Tally/Tally.entitlements Tally.xcodeproj/project.pbxproj
plutil -extract UIBackgroundModes json -o - /private/tmp/tally-issue1-release-derived-data/Build/Products/Release-iphoneos/Tally.app/Info.plist
plutil -extract NSHealthShareUsageDescription raw -o - /private/tmp/tally-issue1-derived-data/Build/Products/Debug-iphonesimulator/Tally.app/Info.plist
plutil -extract NSHealthUpdateUsageDescription raw -o - /private/tmp/tally-issue1-release-derived-data/Build/Products/Release-iphoneos/Tally.app/Info.plist
git diff --check
```

The merged Info.plist contains the `remote-notification` array and retained Health read/write purpose descriptions. The only build warning is skipped App Intents metadata extraction because the app has no App Intents dependency; no unrelated Intents feature was added.

## Test coverage and regression review

The 18 sync-focused unit tests use real local SwiftData containers and CloudKit record/asset conversion without contacting iCloud or Health. They cover:

- an on-disk legacy SavedDrink-only store upgraded to the additive schema;
- original UUID, optional nil/zero values, estimate markers, favourites and local usage surviving migration;
- all template fields merging while existing local usage counters/dates are preserved;
- creation, edits, favourites and deletions staging with local saves, but logging statistics not staging;
- pending deletions surviving a disk-store reopen, and rollback after invalid edits;
- stable identity, stale upload acknowledgements, timestamp precision echoes, clock rollback and deterministic conflicts;
- explicit account-switch consent and removal of old-account checkpoint/change-tag/tombstone state;
- removed-zone pause/recovery preserving the local library;
- CloudKit metadata/asset round trips and upload acknowledgement independent of cached asset availability;
- JSON snapshot restoration as new copies, unchanged current templates, zeroed usage and idempotent ordinary import;
- default-off sync, unavailable cloud access, and local-safe authentication/quota/network/permission error presentation;
- a local performance measurement decoding a 500-template snapshot.

Existing validation, JSON compatibility, Health grouping/conversion, date boundaries, template library, optional nutrition, and historical edit/delete regression tests remain included. The two new UI tests exercise opt-in confirmation, unavailable-cloud feedback with a usable local library, visible backup/restore actions, dark appearance and accessibility-size layouts. Existing UI tests cover general nutrition creation/logging, search, preferences, permissions/errors, light/dark layouts and accessibility descriptions.

UI tests explicitly prohibit CloudKit access and use synthetic Health data plus an in-memory library. Error-presentation tests inject `CKError` values; they do not reproduce real server quota/account conditions. No simulator or unit result is presented as live cloud verification or physical-device verification. Spoken VoiceOver and real Health sample checks were not performed in this task.

## Development failures and fixes

The first unit run executed 49 cases with one failed deletion assertion. A persisted property named `isDeleted` collided with SwiftData’s model-lifecycle semantics. It was renamed `tombstone`, with a disk-reopen regression test. That Xcode invocation also stalled during result finalization after reporting its tests; it was terminated and is not counted as a successful run. Its exact command was:

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=76AC15DD-B86E-4B93-BFD1-E938EFF2BBD5' -derivedDataPath /private/tmp/tally-issue1-derived-data -resultBundlePath /private/tmp/tally-issue1-unit-tests.xcresult -parallel-testing-enabled NO -only-testing:TallyTests test CODE_SIGNING_ALLOWED=NO
```

An initial Simulator compile exposed a throwing-expression syntax error in first-connection staging; it was corrected before the successful build. The first complete suite ran the final complete-suite command with result path `tally-issue1-complete-tests.xcresult`; 63 tests passed and two new UI assertions failed. Captured accessibility hierarchies showed the native combined label “Library sync, Needs attention”, rather than a separate status element. The native compact confirmation is a popover without a Cancel row; the test now dismisses it with an actual outside tap. The initial system-text run used result path `tally-issue1-large-text-tests.xcresult` with the focused command above; its navigation-bar dismissal failed to hit the obscured bar. The corrected outside-tap run passed and its screenshots were opened.

A subsequent complete run with result path `tally-issue1-final-tests.xcresult` passed **65 tests** before the final zone-removal/error regression additions. The final reviewed run above includes those additions. No failed diagnostic run is counted as a pass.

## Remaining prerequisites

Sign into the Apple Developer account in Xcode, create/select `iCloud.gale-k.Tally`, and regenerate provisioning with CloudKit and Push Notifications. Retry the signed build, then install and launch the actual new signed build on the physical iPhone. Only then perform the synthetic-data two-device checklist in [ICLOUD_SYNC.md](ICLOUD_SYNC.md#two-device-verification-still-required), including manual iCloud Drive export/recovery. Check/deploy the CloudKit Production schema before distribution.

Issue #1 remains open: local compiler/model/UI evidence does not satisfy its live two-device acceptance criteria. No push, pull request, merge, or issue closure is performed for this task. Task-specific DerivedData, logs, result bundles, diagnostic exports and the isolated QA simulator are removed after verification; the documentation is retained as the verification record.
