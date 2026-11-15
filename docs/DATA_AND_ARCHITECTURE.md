# Data and architecture

## Ownership

`SavedDrink` remains the template model; its legacy name and persisted properties are retained for compatibility, and it now represents both foods and drinks. It stores template details, optional nutrient amounts, per-nutrient estimate markers, favourites, and convenience usage statistics. The single local `ModelContainer` explicitly disables automatic SwiftData CloudKit integration and now adds local-only `TemplateSyncState` and `LibrarySyncConfiguration` entities. The unique UUID constraint is unchanged; the optional `weightG` property is an additive schema change, while existing `volumeMl` values retain their meaning; an actual on-disk legacy-store upgrade is tested. `LibrarySyncManager` uses `CKSyncEngine` to transfer only the explicit template DTO, avoiding automatic upload of local usage statistics. Editors use a `DrinkDraft` snapshot and commit through `DrinkLibrary`; saves surface errors and roll back failed local changes.

`NutritionValues` and `Nutrient` centralise optional semantics, display, units, and input validation. User-entered nutrition must be finite and nonnegative. Typing-error bounds are 10,000 mg caffeine, 50,000 kcal, and 10,000 g for each other nutrient; these are input constraints, not health guidance. The optional serving amount must be greater than zero and at most 100,000 in the selected unit (`ml` or `g`). The editor stores exactly one of `volumeMl` and `weightG`, clearing the other on a unit switch. This describes the serving only and never rescales its nutrition.

`NutritionStore` abstracts Health operations. `HealthKitStore` is the system adapter, while `HealthKitManager` coordinates transient query results and saving state. The views receive that manager through the SwiftUI environment. Health history is never persisted as a second database.

## General nutrition presentation

Category raw values are additive: meal, snack, fruit/vegetables, and dairy/alternatives join the existing beverage values. No stored field or JSON key is renamed. New templates default to category `other` and serving style `other`; the latter displays as “Not specified”, so food never requires a hot/iced style or liquid volume. Existing coffee/hot and other selections are retained when editing. The additive `cold` serving-style raw value describes chilled items separately from `iced`. Snack uses a template vector wrapped-sweet asset in rows, cards, and confirmation.

`Nutrient.formOrder` defines the balanced editor order. `NutritionValues.displayNutrients`, `summaryNutrients`, and `summaryText` select only known amounts for cards and history, retaining zeroes and estimate markers. Caffeine-only drinks still display their caffeine; protein-only and other food entries receive meaningful summaries without a made-up caffeine value.

Today uses equal-weight calorie/protein/sugar/caffeine cards. The original `showCalories`, `showSugar`, and personal-target preference keys remain; independent `showProtein` and `showCaffeine` settings control the new presentation. The caffeine chart follows its visibility setting. These are presentation preferences only and do not alter Health permissions or supported nutrients.

## Saving a consumption event

Confirmation creates an independent `ConsumptionDraft`, with one UUID and one timestamp. Only present values become `HKQuantitySample`s. Caffeine uses `gramUnit(with: .milli)`, energy uses `kilocalorie()`, and other supported nutrients use `gram()`.

The adapter checks Health availability and exposed write authorization for every present nutrient. It saves the complete sample array in one call. The installed SDK documents that if any object cannot be saved, none of that array is saved. This avoids silently logging only part of an entry when permissions are incomplete.

Samples use `HKMetadataKeyFoodType` and `HKMetadataKeyWasUserEntered`, plus reverse-DNS custom keys for event ID, brand, size, and that sample’s estimate flag. No local template relationship is required to read the historical event later.

After Health succeeds, the local template’s usage count and most recent consumption time are updated. A local save failure cannot undo the successful Health write: the sheet explicitly says the drink was saved to Health, prevents another submission, and reports the local issue. Quick Add uses the same ordering when creating an optional reusable template.

## Queries, privacy, and grouping

The adapter requests exactly the eight supported quantity types. `isHealthDataAvailable()` gates access. Permission-sheet completion is recorded only as “permissions requested”; it never becomes a universal read-authorized flag. Write statuses are displayed only where HealthKit exposes them.

The iOS 27 `earliestAuthorizedSampleDate(for:)` API clamps queries for types with a limited read window. An omitted type cannot distinguish full access from denial. Missing samples remain missing, including in daily cards and chart bars.

Recent history is a rolling window of 30 calendar days. Totals sum visible samples from all sources; day boundaries use the current calendar and half-open intervals, including daylight-saving transitions. The seven-day chart preserves estimate markers and omits bars when no sample is visible.

Only samples whose source bundle matches Tally may be grouped by Tally event metadata. Legacy Tally samples without an event identifier may be grouped by their exact timestamp. Every other app’s sample remains separate, even if it has copied metadata or a matching timestamp. The source name remains visible. History details expose all available nutrients.

The dashboard refreshes after logging, when returning to the foreground, and on pull-to-refresh. Refresh generations prevent a stale overlapping response from replacing a newer response. Query failures remain visible alongside any previously refreshed data and its timestamp.

The event-name fallback is now “Nutrition entry” when no food-type metadata is present. Existing names from Health are used verbatim, including historical drinks. Metadata keys, bundle identity, and grouping rules are unchanged.

## Library JSON, version 1

The root object has `version: 1` and `drinks: [SavedDrinkRecord]`. Records include identity, template details, nutrition and estimate flags, favourites, and creation/update timestamps. Dates use ISO 8601. There are no Health samples, consumption timestamps, or usage counts in the export. Imported templates start with a zero usage count and no last-logged date. Optional `weightG` is carried through snapshots and sync payloads; older records without it continue to decode as millilitres or an unspecified amount. Transfers reject records containing both weight and volume.

Import validates the complete document before insertion. Duplicate IDs within a file, unsupported versions, malformed or invalid data, files over 5 MB, and libraries over 5,000 records fail without importing a partial library. Existing UUIDs are skipped rather than overwritten. Missing records and their sync outbox entries are saved in one SwiftData batch. Explicit “Restore Snapshot as New Copies” first validates the same version-1 format, then assigns every restored item a new UUID after confirmation. It preserves template fields and resets usage, without changing existing templates. Import/restore never writes to Health. The snapshot is an independent user-directed Files/iCloud Drive backup, not an automatic archive of live sync.

## Optional private iCloud sync

`LibrarySyncStore` commits a versioned template payload, monotonic edit timestamp, revision UUID, and pending flag in the same transaction as creation, edit, favourite, duplicate, deletion, import, or development seeding. Local usage updates do not stage a revision. Remote merges update only template fields, preserving this device’s usage counters and leaving HealthKit untouched. All preferences, including Health permission-request state, stay device-local.

`LibrarySyncManager` owns the private-database engine, account binding, checkpoint serialization, error/status presentation, and silent notification registration. Its delegate is in `LibrarySyncDelegate.swift`; `CloudTemplateCodec` owns secure record-system-field encoding and bounded JSON `CKAsset` conversion. Account/engine identity is rechecked around asynchronous fetch and upload preparation. Local persistence/validation failures detach the engine before checkpointing can skip unapplied data.

Records use the template UUID in the `TallyLibrary` private zone of `iCloud.gale-k.Tally`. Whole-template last-change-wins compares the explicit edit date, then favours a deletion on a tie, then compares revision UUIDs lexically for deterministic resolution. Local edits sort after the known revision even if the local clock moved backwards. Identical revision echoes are accepted despite server date precision changes. A late upload acknowledgement clears pending state only for the matching revision. Initial connection uses existing edit dates, so merely connecting an older snapshot does not make it newer than a remote edit.

Deletions are durable tombstone records without a template payload, preventing older offline versions from reappearing. No retention period or automatic pruning is applied. Devices with unsynchronised later edits follow the same resolution policy; there is no multi-version conflict browser. Different physical device clocks can affect whole-template conflict ordering; export snapshots for independent recovery. Physical CloudKit record deletion is reconciled separately; pending local edits may recreate that record. The account-bound `zoneEstablished` flag prevents launch from recreating a previously established zone. Removal of the entire private zone pauses sync and requires explicit reconnection before publishing local data again.

Switching/signing out of iCloud pauses sync and keeps local templates. The previous account binding is retained. Connecting the retained library to a different account requires a separate confirmation; only then are the old account’s engine checkpoint, record change tags, and tombstones discarded locally. The previous account’s remote library is not deleted. This deliberately merges the retained local templates into the newly selected account, as the confirmation explains.

Conflict errors can reference a server record without a locally downloadable asset. The delegate explicitly fetches the complete current server copy and rechecks engine/account identity before merging. Manual sending retries only complete optimistic-save conflicts after the delegate resolves them; other or mixed errors remain visible. Replayed zone-deletion notices cannot revoke an explicit reconnection while its new zone creation is pending.

“Connected” means no local pending changes, not proof that every other device is current. “Last completed exchange” records a completed exchange, after any expected conflicts are resolved, with no remaining local changes. Scheduling and transient network retries are owned by `CKSyncEngine`; foreground/manual sync also checks account identity and fetches before sending. Permanent errors retain pending data and require a retry. See [iCloud sync and recovery](ICLOUD_SYNC.md) for setup, operational behaviour, and recovery.

## Development fixtures

`DevelopmentData.swift` contains only six synthetic food and drink Debug presets; demonstration amounts are not a nutrition reference. The original `developmentPresetsSeeded.v1` marker is retained, so upgrades never insert a second batch. The persistent once-only marker is set after a successful batch save. Normal app launches do not auto-seed.

`UITestFixtures.swift` is Debug-only. `--ui-testing` selects an in-memory SwiftData store and `FixtureNutritionStore`. CloudKit access is also prohibited in this mode. The separate Debug-only `--isolated-test-host` flag provides an empty app store and fake Health adapter without resetting preferences, for opt-in physical live tests whose clients have their own stores, zones, assets and subscriptions. Additional arguments select seeded templates, synthetic history, dark appearance, accessibility text sizes, and permission/query failure states. These test arguments and synthetic health samples do not exist in Release behavior.

Shortcuts, widgets, controls, photos, and undo are optional follow-up features; the core app does not expose them.

The [live verification guide](LIVE_ICLOUD_VERIFICATION.md) documents the explicitly gated physical CloudKit and Mac iCloud Drive helpers, actual results, cleanup, and limits. Ordinary suites skip the live test.
