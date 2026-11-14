import XCTest
import SwiftData
import CloudKit
@testable import Tally

/// These tests exercise real local persistence and CloudKit record conversion without contacting iCloud or Health.
@MainActor
final class SyncTests: XCTestCase {
    private func store() throws -> ModelContainer {
        let result = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        result.mainContext.autosaveEnabled = false
        return result
    }
    private func change(_ item: SavedDrink, date: Date, deleted: Bool = false, revision: String = UUID().uuidString) -> CloudTemplateChange {
        .init(id: item.id, modifiedAt: date, revision: revision, template: deleted ? nil : SavedDrinkRecord(item))
    }
    func testLocalMutationsStageAtomicallyButUsageDoesNotSync() throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Lunch"; draft.values[.protein] = "18"
        let item = try DrinkLibrary.save(draft, in: context)
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context))
        let revision = row.revision
        try DrinkLibrary.recordLog(for: item, at: .now, in: context)
        XCTAssertEqual(row.revision, revision)
        XCTAssertEqual(item.timesLogged, 1)
        let encoded = String(data: try XCTUnwrap(row.payload), encoding: .utf8)!
        for excluded in ["lastLoggedAt", "timesLogged", "healthPermissionsRequested", "samples", "history"] { XCTAssertFalse(encoded.contains(excluded)) }
        try DrinkLibrary.toggleFavourite(item, in: context)
        XCTAssertNotEqual(row.revision, revision)
        XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.change(row).template).isFavourite)
        try DrinkLibrary.delete(item, in: context)
        XCTAssertTrue(row.tombstone); XCTAssertNil(row.payload); XCTAssertTrue(row.needsUpload)
    }
    func testInvalidEditDoesNotLeavePartialOutboxChanges() throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Coffee"; draft.values[.caffeine] = "100"
        let item = try DrinkLibrary.save(draft, in: context)
        let revision = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).revision
        draft.values[.caffeine] = "-1"
        XCTAssertThrowsError(try DrinkLibrary.save(draft, editing: item, in: context))
        XCTAssertEqual(item.caffeineMg, 100)
        XCTAssertEqual(try LibrarySyncStore.state(for: item.id, in: context)?.revision, revision)
        XCTAssertFalse(context.hasChanges)
    }
    func testFirstConnectionPreservesIdentityAndOriginalEditOrdering() throws {
        let container = try store(); let context = container.mainContext
        let edited = Date(timeIntervalSince1970: 1_700_000_000)
        let item = SavedDrink(name: "Legacy", nutrition: .init(caffeine: 0, protein: 6, estimated: [.caffeine]), updatedAt: edited, lastLoggedAt: .now, timesLogged: 9)
        context.insert(item); try context.save()
        let config = try LibrarySyncStore.configuration(in: context)
        XCTAssertFalse(config.enabled)
        try LibrarySyncStore.connect(accountID: "account-A", configuration: config, allowAccountChange: false, in: context)
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context))
        XCTAssertEqual(row.modifiedAt, edited)
        XCTAssertEqual(try LibrarySyncStore.change(row).template?.id, item.id)
        XCTAssertEqual(item.timesLogged, 9); XCTAssertNotNil(item.lastLoggedAt)
        XCTAssertTrue(config.enabled); XCTAssertEqual(config.accountID, "account-A")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
    }
    func testAccountSwitchRequiresExplicitChoiceAndDropsOldAccountMetadata() throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Food"
        let item = try DrinkLibrary.save(draft, in: context)
        let config = try LibrarySyncStore.configuration(in: context)
        try LibrarySyncStore.connect(accountID: "account-A", configuration: config, allowAccountChange: false, in: context)
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)); row.systemFields = Data([1])
        config.zoneEstablished = true
        let deletedID = UUID(); try LibrarySyncStore.stageDeletion(deletedID, in: context); try context.save()
        XCTAssertThrowsError(try LibrarySyncStore.connect(accountID: "account-B", configuration: config, allowAccountChange: false, in: context))
        XCTAssertEqual(config.accountID, "account-A")
        XCTAssertEqual(try LibrarySyncStore.state(for: item.id, in: context)?.systemFields, Data([1]))
        try LibrarySyncStore.connect(accountID: "account-B", configuration: config, allowAccountChange: true, in: context)
        XCTAssertEqual(config.accountID, "account-B"); XCTAssertFalse(config.zoneEstablished)
        XCTAssertNil(try LibrarySyncStore.state(for: deletedID, in: context))
        XCTAssertNil(try LibrarySyncStore.state(for: item.id, in: context)?.systemFields)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
        XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).needsUpload)
    }
    func testRemoteEditMergesWithoutDuplicatingOrOverwritingLocalUsage() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Coffee", nutrition: .init(caffeine: 100), lastLoggedAt: .now, timesLogged: 7)
        context.insert(item); try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 10)); try context.save()
        let remote = SavedDrink(id: item.id, name: "Updated", brandOrLocation: "Example", size: "One serving", volumeMl: 330,
                                category: .meal, servingStyle: .bottle,
                                nutrition: .init(caffeine: 110, sugar: 12, carbohydrates: 20, protein: 0, totalFat: 3, saturatedFat: 1, fibre: 2, estimated: [.caffeine, .sugar]),
                                notes: "Serving notes", isFavourite: true)
        let incoming = change(remote, date: Date(timeIntervalSince1970: 20))
        try LibrarySyncStore.receive(incoming, systemFields: nil, in: context); try context.save()
        XCTAssertEqual(item.name, "Updated"); XCTAssertEqual(item.caffeineMg, 110); XCTAssertEqual(item.proteinG, 0)
        XCTAssertNil(item.caloriesKcal); XCTAssertTrue(item.isFavourite)
        XCTAssertEqual(item.timesLogged, 7); XCTAssertNotNil(item.lastLoggedAt)
        XCTAssertEqual(SavedDrinkRecord(item), SavedDrinkRecord(remote))
        XCTAssertFalse(try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).needsUpload)
        try LibrarySyncStore.receive(incoming, systemFields: nil, in: context); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
    }
    func testNewerLocalEditAndStaleAcknowledgementStayPending() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Original"); context.insert(item)
        try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 20)); try context.save()
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context))
        let sent = try LibrarySyncStore.change(row)
        item.name = "Newer"; try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 30)); try context.save()
        try LibrarySyncStore.acknowledge(id: sent.id, revision: sent.revision, systemFields: Data([2]), in: context); try context.save()
        XCTAssertTrue(row.needsUpload); XCTAssertEqual(try LibrarySyncStore.change(row).template?.name, "Newer")
        try LibrarySyncStore.receive(sent, systemFields: Data([3]), in: context); try context.save()
        XCTAssertEqual(item.name, "Newer"); XCTAssertTrue(row.needsUpload)
        try LibrarySyncStore.acknowledge(id: row.id, revision: row.revision, systemFields: Data([4]), in: context); try context.save()
        XCTAssertFalse(row.needsUpload)
    }
    func testDeletionWinsTimestampTieAndOldRevisionsCannotResurrect() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Food")
        let date = Date(timeIntervalSince1970: 20)
        let edit = change(item, date: date)
        let deletion = change(item, date: date, deleted: true)
        XCTAssertTrue(edit.precedes(deletion)); XCTAssertFalse(deletion.precedes(edit))
        try LibrarySyncStore.receive(deletion, systemFields: nil, in: context); try context.save()
        try LibrarySyncStore.receive(edit, systemFields: nil, in: context); try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 0)
        XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).tombstone)
    }
    func testStableRevisionTieBreakAndClockMovingBackwards() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Food"); context.insert(item)
        try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 100)); try context.save()
        try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 50)); try context.save()
        XCTAssertGreaterThan(try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).modifiedAt, Date(timeIntervalSince1970: 100))
        let a = change(item, date: .now, revision: "00000000-0000-0000-0000-000000000001")
        var b = a; b.revision = "00000000-0000-0000-0000-000000000002"
        XCTAssertTrue(a.precedes(b)); XCTAssertFalse(b.precedes(a))
    }
    func testEchoWithSameRevisionDoesNotRequeueAfterTimestampRounding() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Food"); context.insert(item)
        try LibrarySyncStore.stage(item, in: context, now: Date(timeIntervalSince1970: 100.123456)); try context.save()
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context))
        var echo = try LibrarySyncStore.change(row); echo.modifiedAt = Date(timeIntervalSince1970: 100.123)
        try LibrarySyncStore.receive(echo, systemFields: nil, in: context); try context.save()
        XCTAssertFalse(row.needsUpload)
    }
    func testInvalidRemoteRecordCannotPartiallyApply() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Food")
        let valid = change(item, date: .now)
        var invalid = valid; invalid.template?.nutrition.protein = -1
        do {
            try LibrarySyncStore.receive(valid, systemFields: nil, in: context)
            try LibrarySyncStore.receive(invalid, systemFields: nil, in: context)
            XCTFail("Expected invalid data")
        } catch { context.rollback() }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 0)
    }
    func testCloudRecordRoundTripAndAssetPayloadExcludesUsage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyCloudCodec-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = SavedDrink(name: "Food", category: .meal, nutrition: .init(caffeine: 0, calories: 250, protein: 18, estimated: [.protein]), lastLoggedAt: .now, timesLogged: 12)
        let original = change(item, date: .now)
        let record = try CloudTemplateCodec.record(for: original, systemFields: nil, assetDirectory: folder)
        XCTAssertEqual(try CloudTemplateCodec.change(from: record), original)
        let fields = CloudTemplateCodec.systemFields(record)
        let restored = try CloudTemplateCodec.record(for: original, systemFields: fields, assetDirectory: folder)
        XCTAssertEqual(restored.recordID, record.recordID)
        let payload = try XCTUnwrap((record["template"] as? CKAsset)?.fileURL)
        let json = try String(contentsOf: payload, encoding: .utf8)
        XCTAssertFalse(json.contains("timesLogged")); XCTAssertFalse(json.contains("lastLoggedAt"))
        var deletion = original; deletion.template = nil
        // An acknowledgement must remain readable after the SDK/local cache releases the payload file.
        try FileManager.default.removeItem(at: payload)
        let acknowledgement = try CloudTemplateCodec.acknowledgedRevision(from: record)
        XCTAssertEqual(acknowledgement.id, original.id); XCTAssertEqual(acknowledgement.revision, original.revision)
        let tombstone = try CloudTemplateCodec.record(for: deletion, systemFields: fields, assetDirectory: folder)
        XCTAssertNil(tombstone["template"])
        XCTAssertTrue(try CloudTemplateCodec.change(from: tombstone).isDeleted)
    }
    func testSnapshotRestoreCopiesKeepsCurrentTemplatesAndResetsUsage() throws {
        let container = try store(); let context = container.mainContext
        let item = SavedDrink(name: "Old", nutrition: .init(caffeine: 100, estimated: [.caffeine]), timesLogged: 9)
        let snapshot = try DrinkExportService.export([item])
        item.name = "Current"; item.caffeineMg = 110; context.insert(item); try context.save()
        let report = try DrinkExportService.importDrinks(snapshot, into: context, mode: .restoreCopies)
        XCTAssertTrue(report.restoredCopies); XCTAssertEqual(report.imported, 1)
        let items = try context.fetch(FetchDescriptor<SavedDrink>())
        XCTAssertEqual(items.count, 2)
        let copy = try XCTUnwrap(items.first { $0.id != item.id })
        XCTAssertEqual(copy.name, "Old"); XCTAssertEqual(copy.caffeineMg, 100)
        XCTAssertEqual(item.name, "Current"); XCTAssertEqual(item.timesLogged, 9)
        XCTAssertEqual(copy.timesLogged, 0); XCTAssertNil(copy.lastLoggedAt)
        XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.state(for: copy.id, in: context)).needsUpload)
        XCTAssertEqual(try DrinkExportService.importDrinks(snapshot, into: context).imported, 0)
    }
    func testLegacyDiskStoreMigratesAdditivelyWithoutChangingTemplates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyMigration-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        let id = UUID(); let logged = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let legacy = try ModelContainer(for: SavedDrink.self, configurations: configuration)
            legacy.mainContext.insert(SavedDrink(id: id, name: "Coffee", category: .coffee, servingStyle: .iced,
                                                nutrition: .init(caffeine: 0, protein: 6, estimated: [.caffeine]), isFavourite: true, lastLoggedAt: logged, timesLogged: 12))
            try legacy.mainContext.save()
        }
        let upgraded = try LibraryStore.container(configuration: configuration)
        let item = try XCTUnwrap(upgraded.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertEqual(item.id, id); XCTAssertEqual(item.caffeineMg, 0); XCTAssertNil(item.caloriesKcal)
        XCTAssertEqual(item.nutrition.estimated, [.caffeine]); XCTAssertTrue(item.isFavourite)
        XCTAssertEqual(item.timesLogged, 12); XCTAssertEqual(item.lastLoggedAt, logged); XCTAssertEqual(item.servingStyle, .iced)
        XCTAssertFalse(try LibrarySyncStore.configuration(in: upgraded.mainContext).enabled)
    }
    func testPendingDeletionSurvivesStoreReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyOutbox-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        let id: UUID
        do {
            let container = try LibraryStore.container(configuration: configuration)
            var draft = DrinkDraft(); draft.name = "Deleted offline"
            let item = try DrinkLibrary.save(draft, in: container.mainContext); id = item.id
            try DrinkLibrary.delete(item, in: container.mainContext)
        }
        let reopened = try LibraryStore.container(configuration: configuration)
        let row = try XCTUnwrap(LibrarySyncStore.state(for: id, in: reopened.mainContext))
        XCTAssertTrue(row.tombstone); XCTAssertTrue(row.needsUpload)
        XCTAssertTrue(try LibrarySyncStore.change(row).isDeleted)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<SavedDrink>()), 0)
    }

    func testSyncDefaultsOffAndUnavailableCloudKeepsLocalLibrary() async throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Offline item"
        _ = try DrinkLibrary.save(draft, in: context)
        let manager = try LibrarySyncManager(context: context, allowsCloudAccess: false)
        XCTAssertFalse(manager.enabled); XCTAssertNil(manager.engine)
        await manager.startIfNeeded()
        XCTAssertNil(manager.errorMessage)
        await manager.enable()
        XCTAssertFalse(manager.enabled); XCTAssertNil(manager.engine)
        XCTAssertEqual(manager.status, "Needs attention"); XCTAssertNotNil(manager.errorMessage)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
        manager.disable()
        XCTAssertEqual(manager.status, "Off"); XCTAssertNil(manager.errorMessage)
    }

    func testRemovedEstablishedZonePausesWithoutDiscardingLocalTemplates() throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Retained local item"
        let item = try DrinkLibrary.save(draft, in: context)
        let manager = try LibrarySyncManager(context: context, allowsCloudAccess: false)
        try LibrarySyncStore.connect(accountID: "account-A", configuration: manager.configuration, allowAccountChange: false, in: context)
        manager.configuration.zoneEstablished = true; manager.configuration.engineState = Data([1])
        let row = try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context))
        row.needsUpload = false; row.systemFields = Data([2]); try context.save()
        try manager.pauseForMissingZone()
        XCTAssertFalse(manager.enabled); XCTAssertFalse(manager.configuration.enabled)
        XCTAssertFalse(manager.configuration.zoneEstablished); XCTAssertNil(manager.configuration.engineState)
        XCTAssertTrue(row.needsUpload); XCTAssertNil(row.systemFields)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
        XCTAssertEqual(manager.pendingAccountID, "account-A")
    }

    func testCloudServiceErrorsKeepTemplatesAndPendingEdits() throws {
        let container = try store(); let context = container.mainContext
        var draft = DrinkDraft(); draft.name = "Offline food"
        let item = try DrinkLibrary.save(draft, in: context)
        let manager = try LibrarySyncManager(context: context, allowsCloudAccess: false)
        for code: CKError.Code in [.notAuthenticated, .quotaExceeded, .networkUnavailable, .permissionFailure] {
            manager.show(CKError(code))
            XCTAssertEqual(manager.status, "Needs attention"); XCTAssertNotNil(manager.errorMessage)
            XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.state(for: item.id, in: context)).needsUpload)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SavedDrink>()), 1)
            XCTAssertNil(manager.engine)
        }
    }

    func testCustomVerificationZoneCannotDecodeOrReuseProductionRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallyZoneCodec-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let item = SavedDrink(name: "Synthetic")
        let value = change(item, date: .now)
        let zone = CKRecordZone.ID(zoneName: "TallyCloudVerification-" + UUID().uuidString)
        let record = try CloudTemplateCodec.record(for: value, systemFields: nil, assetDirectory: folder, zoneID: zone)
        XCTAssertEqual(record.recordID.zoneID, zone)
        XCTAssertEqual(try CloudTemplateCodec.change(from: record, zoneID: zone), value)
        XCTAssertThrowsError(try CloudTemplateCodec.change(from: record))
        XCTAssertThrowsError(try CloudTemplateCodec.acknowledgedRevision(from: record))
        XCTAssertThrowsError(try CloudTemplateCodec.record(for: value, systemFields: CloudTemplateCodec.systemFields(record), assetDirectory: folder))
    }

    func testOnlyCompleteRecordConflictsAreTreatedAsResolvedRetries() throws {
        let record = CKRecord(recordType: CloudTemplateCodec.recordType)
        let conflict = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: record])
        XCTAssertTrue(CloudSyncFailure.isRecordConflict(conflict))
        let partial = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["item": conflict]])
        XCTAssertTrue(CloudSyncFailure.isRecordConflict(partial))
        let mixed = CKError(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: ["conflict": conflict, "quota": CKError(.quotaExceeded)]])
        XCTAssertFalse(CloudSyncFailure.isRecordConflict(mixed))
        XCTAssertFalse(CloudSyncFailure.isRecordConflict(CKError(.partialFailure)))
        XCTAssertFalse(CloudSyncFailure.isRecordConflict(CKError(.serverRecordChanged)))
        XCTAssertFalse(CloudSyncFailure.isRecordConflict(CKError(.notAuthenticated)))
        XCTAssertFalse(CloudSyncFailure.isRecordConflict(CKError(.networkFailure)))
    }

    func testSnapshotDecodePerformance() throws {
        // A realistic larger template library exercises optional values, estimates, dates, and notes during backup recovery.
        let data = try DrinkExportService.export((0..<500).map { SavedDrink(name: "Food \($0)", nutrition: .init(calories: 250, protein: 18, estimated: [.protein]), notes: String(repeating: "Serving note. ", count: 20)) })
        measure { do { _ = try DrinkExportService.decode(data) } catch { XCTFail(error.localizedDescription) } }
    }
}
