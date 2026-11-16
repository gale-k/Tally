# Live iCloud verification — 14 November 2026

All builds, tests, and verification ran locally on Kai’s Mac with Xcode 27.0 (27A266a) and isolated DerivedData under `/private/tmp`. No GitHub-hosted Actions were triggered or used. One physical iPhone 17 Pro Max running iOS 27.2 was available; a second physical iPhone was unavailable.

## Results and limits

| Check | Actual environment | Result |
| --- | --- | --- |
| Account access, CKRecord/CKAsset save and fetch, all template fields, unknown/zero/estimate preservation | Physical iPhone, private Development CloudKit | Passed |
| Create, edit, favourite, repeated sync without duplicate UUIDs | Three isolated local clients on that iPhone | Passed |
| Local usage excluded from cloud payload and preserved during remote merge | Physical iPhone and actual fetched asset | Passed |
| Paused sync, pending outbox persisted, local store reopened, live reconnect | Physical iPhone | Passed; this is not an airplane-mode test |
| Stale upload with a later server winner and with a later local winner | Actual CloudKit optimistic-save conflicts | Both passed |
| Deletion versus an earlier queued edit; fresh-client recovery | Actual CloudKit, independent local stores | Passed |
| Removed scratch zone pauses syncing; explicit reconnection recreates it | Actual CloudKit | Passed |
| JSON read/import idempotency and restore as new identities | Physical iPhone, synthetic version-1 snapshot | Passed |
| Snapshot upload confirmed, local copy evicted, downloaded again, byte equality and import/restore checked | This Mac’s iCloud Drive account | Passed |
| Regression suite | Isolated iOS 27 iPhone Simulator | 69 passed, 0 failed, 1 intentionally skipped live test; 0 runtime warnings in result summary |
| Separate live integration suite | Physical iPhone | 1 passed, 0 failed, 0 skipped; 0 runtime warnings in result summary |
| Release iPhone target compilation | Mac, unsigned Release build | Passed; test-host/fixture flags absent from the Release executable |
| Corrected normal app installation and launch | Physical iPhone | Passed; normal app restored and its running process confirmed |
| Two physical iPhones, remote notification delivery and convergence between them | Second iPhone unavailable | Unverified |
| Native iPhone Files picker export/import, physical network loss, OS-level account switch/sign-out, real quota exhaustion | Not exercised | Unverified |
| Production CloudKit schema deployment/runtime | Not contacted | Unverified |

The live test uses the real CloudKit service through the app’s manager, delegate, codec, and persistence layer. Three local clients in one process establish server exchange/conflict behaviour, not two-device convergence or background delivery. Automatic background scheduling was not exercised: exchanges were explicitly driven during the test. The Mac iCloud Drive result establishes actual cloud upload/download of the app’s JSON format; it does not establish the iPhone Files-picker flow or that both devices use the same iCloud Drive account. Issue #1 remains open for those remaining acceptance checks.

## Isolation and cleanup

`LiveCloudKitTests` is skipped in ordinary runs. `Scripts/run_live_cloud_checks.py` requires explicit `--allow-live-cloud`, creates a fresh signed test host, and refuses to run unless its effective CloudKit entitlement is `Development` and the container is `iCloud.gale-k.Tally`.

The Debug-only `--isolated-test-host` argument uses an empty in-memory app library and fake Health adapter without resetting device preferences. The live test’s clients each use their own SQLite store, asset directory and named database subscription. Their custom zone is `TallyCloudVerification-<UUID>`. The normal `TallyLibrary` zone, real templates and Health history are outside the test. No Health logging was performed by either verification helper.

The test persists a recovery manifest before remote writes, validates the owned zone prefix/UUID before cleanup, and removes only that scratch zone and its three explicitly named subscriptions. It can clean an interrupted prior run on the next opt-in invocation. The successful run confirmed cleanup. Development schema definitions for the app’s `TallyTemplate` record type remain; no Production schema was deployed.

The Mac helper writes one uniquely named synthetic JSON snapshot in iCloud Drive, confirms the system’s uploaded state, evicts only that file’s local copy, requests download, validates/restores the bytes, and removes only its own snapshot. Its final cleanup checkpoint passed. Task-specific build products, module caches, result bundles, logs, diagnostic exports and the isolated regression Simulator are removed after recording results.

## Live-confirmed defects fixed

1. **Conflict assets and false errors.** The record attached to a real `serverRecordChanged` failure could not be decoded as a complete template. Conflict handling now fetches the full current server record, including its asset, and rechecks engine/account identity before merging. The SDK also throws record conflicts from `sendChanges` after delivering the delegate callback. A bounded retry accepts the resolved server winner or resends a pending local winner, without misreporting that handled conflict as a generic failure. Mixed quota/authentication/transport errors are not suppressed.
2. **Explicit reconnection paused again.** A freshly reconnected engine received the old zone-deletion notice and revoked the user’s new consent. That notice now pauses only an already-established zone; initial creation after explicit reconnection proceeds. The real remove/pause/reconnect scenario passed afterwards.
3. **Unavailable Quick Add symbol.** The physical runtime reported `bolt.badge.plus` as absent. Quick Add now uses the supported, neutral `plus.circle`; subsequent live logs contain no invalid-symbol messages and UI regression tests pass.

Debug and Release CloudKit environments are now explicit: Development for Debug, Production for Release. The app still uses the same container, zone and automatic-sync defaults. Verification supplies isolated routing and manual scheduling through internal constructor defaults; no user-facing testing mode ships in Release.

The first live run failed at the rejected stale upload, the next exposed the incomplete conflict record, and the following run exposed the replayed deletion notice. Every scenario cleaned its scratch resources, including failed runs. The final complete live run passed all checkpoints. A cached test-host product also failed strict signing validation because its asset catalog had been mutated; the runner now performs a clean build and validates the signature and effective environment before allowing live execution. Failed runs are diagnostic evidence, not passed tests.

## Reproduce the live iPhone check

`TALLY_DEVICE_ID` below is the connected physical iPhone identifier; its private value is omitted. The script uses the installed SDK’s generated `.xctestrun` format to opt into just the live case and passes the isolated-host argument. Verbose failure diagnostics are disabled to avoid collecting unrelated device information. Choose a fresh result-bundle path on each run.

```sh
python3 Scripts/run_live_cloud_checks.py --allow-live-cloud --device "$TALLY_DEVICE_ID" --result-bundle /private/tmp/tally-live-cloud-reconnect.xcresult
```

The successful run printed all these checkpoints:

```text
ACCOUNT_AND_OWNED_SUBSCRIPTIONS_READY
CREATE_ASSET_OPTIONAL_ZERO_ESTIMATES_AND_IDEMPOTENCY
EDIT_FAVOURITE_AND_USAGE_BOUNDARY
JSON_READ_IMPORT_IDEMPOTENCY_AND_RESTORE_AS_COPIES
PAUSED_OUTBOX_REOPEN_AND_LIVE_RECONNECT
STALE_UPLOAD_SERVER_REVISION_WINS
STALE_UPLOAD_LOCAL_REVISION_RETRIES_AND_WINS
DELETE_VERSUS_STALE_EDIT_AND_FRESH_CLIENT_RECOVERY
REMOTE_ZONE_REMOVAL_PAUSE_AND_EXPLICIT_RECONNECT
SCRATCH_ZONE_AND_SUBSCRIPTIONS_REMOVED
```

## Reproduce the iCloud Drive format/recovery check

This Mac must already have iCloud Drive available. The helper reuses the app’s actual model, validation, export/import and local merge code; it is not a second backup implementation.

```sh
xcrun swiftc -swift-version 6 -module-cache-path /private/tmp/tally-live-cloud-drive-module-cache -o /private/tmp/tally-live-cloud-drive Tally/Models/NutritionValues.swift Tally/Models/SavedDrink.swift Tally/Models/DrinkDraft.swift Tally/Models/LibrarySyncState.swift Tally/Services/DrinkExportService.swift Tally/Services/Sync/LibrarySyncStore.swift Scripts/verify_icloud_drive.swift
/private/tmp/tally-live-cloud-drive --allow-live-drive
```

The helper reported upload confirmation, local eviction, download/restore verification, and removal of the owned snapshot. The initial temporary helper was also run successfully before the final explicitly gated helper was retained.

## Exact regression, build and deployment commands

The Simulator UUID was task-specific and is deleted after testing; select a current iOS 27 Simulator when repeating. Console redirection is omitted.

```sh
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=iOS Simulator,id=C879471A-CA03-4E3C-B24F-25A90F0D7777' -derivedDataPath /private/tmp/tally-live-cloud-sim-derived-data -resultBundlePath /private/tmp/tally-live-cloud-full-tests.xcresult -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 -collect-test-diagnostics never test CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tally.xcodeproj -scheme Tally -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-live-cloud-release-derived-data build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/tally-live-cloud-device-derived-data -allowProvisioningUpdates build
codesign --verify --strict --verbose=2 /private/tmp/tally-live-cloud-device-derived-data/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 45 device install app --device "$TALLY_DEVICE_ID" /private/tmp/tally-live-cloud-device-derived-data/Build/Products/Debug-iphoneos/Tally.app
xcrun devicectl --timeout 20 device process launch --terminate-existing --device "$TALLY_DEVICE_ID" gale-k.Tally
xcrun devicectl --timeout 20 device info processes --device "$TALLY_DEVICE_ID" --search Tally
git diff --check
```

The first normal-app launch after installation was blocked because the iPhone was locked. After the user unlocked it, the same launch command succeeded and the process check confirmed Tally was running.

A focused unit command also passed 55 tests with the live case intentionally skipped, using the full-suite command with `-only-testing:TallyTests`, result path `tally-live-cloud-unit-tests.xcresult`, and without the two explicit execution-time allowance flags. The final complete suite above supersedes it.

Before the retained runner, signed `build-for-testing` was performed with generic iOS destination and `/private/tmp/tally-live-cloud-derived-data`. Early test-harness compilation errors were corrected before any live invocation. The initial manually prepared live configurations used `Tally_Live_iphoneos27.0-arm64.xctestrun` in that DerivedData’s `Build/Products`, with the same destination, test selector and allowance flags as the runner; the first two used default diagnostic collection. The retained runner adds fresh-build/signature/environment checks and disables that collection. No failed or partially completed invocation is counted as a passed check.
