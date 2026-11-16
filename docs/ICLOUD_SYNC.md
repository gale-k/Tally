# iCloud library sync and recovery

## What syncs

Sync is off by default. In **Settings → iCloud Library**, choose **Enable iCloud Sync** and confirm the merge. Tally uses Apple’s CloudKit private database for the signed-in iCloud account; no Tally account or custom server is involved. Saved food/drink identities, names, brand/location, serving details, all known nutrition, estimate markers, notes, favourites, and template creation/edit dates are included. Blank amounts stay unknown and explicit zeroes stay zero.

Templates remain in the local SwiftData store and can be created, edited, searched, logged, imported, and deleted offline. Pending template changes are saved with the local transaction and can retry after a relaunch. **Sync Now** asks for a fetch/send exchange; automatic scheduling and transient retries depend on the system and network conditions.

The following stay outside Tally’s CloudKit records and JSON snapshots:

- HealthKit samples and queried consumption history;
- Health permission/request state;
- convenience usage counts and last-logged dates;
- Settings preferences such as Today cards and the personal caffeine target.

Health history remains in Apple Health, subject to Apple Health’s own system settings. Library operations never write, edit, or delete consumption samples.

## Conflicts, deletions, and duplicate identities

The UUID identifies a template across devices. Retrying the same revision does not create a second item. Concurrent changes resolve at the whole-template level: the later edit timestamp wins; an exact timestamp tie favours deletion, then a stable lexical revision-UUID order. There is no field-by-field merge or conflict-version browser. Device clock differences can affect which concurrent edit wins; keep snapshots when you want independent recovery.

A local change always sorts after the revision that device has already received. Initial connection preserves original edit ordering rather than treating every existing item as newly edited. A later upload acknowledgement cannot clear an even newer offline edit.

Deleting a template writes a durable deletion marker to iCloud. An older revision cannot resurrect it. A genuinely newer concurrent edit can win under the policy above. A deletion removes the corresponding local template on other devices, including that device’s convenience usage counters; historical Health entries are unaffected. Deletion markers are not automatically pruned.

**Live sync is not a backup.** Changes and deletions reach other devices. Turning sync off keeps both the local library and existing cloud records. Local changes wait for a later reconnection.

## Account changes and status

Sign-out or a different iCloud account pauses sync without deleting the local library. Tally keeps the previous binding. Return to the original account and enable again, or choose **Connect Library to Current Account** and explicitly confirm merging the retained local templates into that account. Old account change tags/checkpoints/deletion markers are discarded locally only after this choice; its remote library is kept. No automatic cross-account merge is performed.

If the entire remote private zone is removed, syncing pauses rather than silently republishing everything. Reconnect explicitly to publish retained local templates again.

“Connected” means no local changes are waiting to upload. It does not prove other devices have sent all their changes. “Last completed exchange” is an error-free send with no local pending changes. Network, sign-in, quota, schema, and local persistence errors are shown without claiming success; the library remains available locally. Permanent errors may require **Sync Now** after correcting the cause.

## Independent manual backup

1. Open **Settings → Backups & Restore → Export Library Snapshot**.
2. Save the JSON document in Files. Choose **iCloud Drive** if you want the snapshot stored there.
3. Give snapshots distinct names/dates to retain older versions; exporting is manual, not scheduled automatically by Tally.
4. To add missing items after reinstalling or changing phones, choose **Import Library** and select the snapshot. Existing UUIDs are skipped, so repeating that import does not duplicate current items.
5. To recover an older template while keeping its current version, choose **Restore Snapshot as New Copies**, select the snapshot, and confirm. Every snapshot item receives a new UUID, so duplicates are expected and existing items are not overwritten. Review/delete unwanted copies afterwards.

The format remains version 1, including the legacy `drinks` key, so exports from before iCloud support remain supported. The complete document is validated before a transactional import. Unsupported versions, duplicate IDs within the file, invalid nutrition, more than 5,000 records, or more than 5 MB fail without partial insertion. Restored/imported items start with zero usage and no last-logged date. When sync is enabled, additions join the normal template outbox. A snapshot does not contain or restore Health history.

## Developer setup

The project targets iOS 27 using the installed Xcode 27 SDK. Signing explicitly selects Development CloudKit for Debug and Production for Release. CloudKit APIs were checked against that SDK’s Swift interfaces before implementation. The original `SavedDrink` schema uses a unique UUID and includes local-only statistics, so automatic SwiftData CloudKit integration stays disabled. The additive local metadata and explicit `CKSyncEngine` transport are described in [architecture notes](DATA_AND_ARCHITECTURE.md). Apple documents [SwiftData CloudKit schema constraints](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) and [CKSyncEngine’s persistence/scheduling responsibilities](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5).

1. Sign into the appropriate Apple Developer account in **Xcode → Settings → Accounts**. Use a team eligible for CloudKit and Push Notifications.
2. In Tally’s **Signing & Capabilities**, create/select container **`iCloud.gale-k.Tally`**, with **iCloud → CloudKit**, **Push Notifications**, and **Background Modes → Remote notifications** enabled. HealthKit must remain enabled. Regenerate/select a provisioning profile containing these capabilities.
3. The app uses the private database, custom zone `TallyLibrary`, and record type `TallyTemplate`. Fields are `version` (integer), `editedAt` (date), `revision` (string), `deleted` (integer/Boolean), and optional `template` (asset). The asset contains only the template DTO, with a 5 MB local bound. Record names are stable template UUIDs. Sync uses zone changes, not application queries.
4. First exercise the Development CloudKit environment using synthetic templates and eligible, signed-in devices. Before TestFlight/App Store distribution, deploy the verified record schema to Production in CloudKit Console and verify the distribution entitlements/environment. This task has not verified production schema deployment.
5. Silent remote notifications are registered only after opt-in. Tally does not request visible notification permission. Signing into iCloud on the phone and enabling Tally’s iCloud access are separate from the developer’s signing account on the Mac.

A checked-in entitlement/container identifier is not evidence that the container exists or that the current provisioning profile supports it. See [issue #1 verification](ISSUE_1_VERIFICATION.md) for actual build results and external prerequisites still outstanding.

## Verification status

[Live verification on one iPhone and this Mac](LIVE_ICLOUD_VERIFICATION.md) passed real CloudKit exchanges/conflicts/recovery and a synthetic iCloud Drive upload/download/restore. These checks use isolated clients and scratch resources, not two physical phones. The native iPhone Files-picker flow, physical network/account/quota cases, and Production environment remain unverified.

## Two-device verification still required

Use synthetic data on two iPhones signed into the same iCloud account. Enable sync explicitly on both, then check creation, every optional field/estimate, edit, favourite, deletion, repeated sync, relaunch, and offline changes followed by reconnect. Make concurrent edits and an edit/deletion conflict and compare the documented winner. Check the absence of duplicate UUIDs and that each phone’s local usage counts/preferences and Health history remain independent.

Export a dated snapshot to iCloud Drive. Verify ordinary import is idempotent and explicit restore-as-copies recovers an older value without overwriting current templates. Check sign-out, account switch with cancelled and confirmed merge, quota/network errors, and private-zone removal. Never delete an existing user’s production zone as a test. Record real outcomes separately from local model/codec tests; simulator fixtures do not establish live CloudKit convergence.
