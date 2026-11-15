import XCTest
import SwiftData
import CloudKit
@testable import Tally

/// Explicitly opt-in, physical-device integration test. Every remote write belongs to a uniquely named scratch zone.
/// The host uses an empty in-memory app library and fake Health adapter; clients below have separate local stores.
@MainActor
final class LiveCloudKitTests: XCTestCase {
    private let prefix = "TallyCloudVerification-"
    private var clients: [Client] = []
    private var checkpoints: [String] = []

    private struct Run: Codable {
        let zoneName: String
        var subscriptions: [String] { ["A", "B", "C"].map { zoneName + "-" + $0 } }
    }
    @MainActor private struct Client {
        let label: String
        let store: ModelContainer
        let sync: LibrarySyncManager
        var context: ModelContext { store.mainContext }
    }
    private struct Failure: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    func testLiveCloudRoundTripAndRecovery() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live checks require the physical iPhone and explicit opt-in.")
        #else
        guard ProcessInfo.processInfo.environment["TALLY_LIVE_CLOUDKIT"] == "1" else {
            throw XCTSkip("Opt in through the documented isolated live xctestrun configuration.")
        }
        guard ProcessInfo.processInfo.arguments.contains("--isolated-test-host") else {
            throw Failure(detail: "Refusing live checks without an isolated app host.")
        }
        executionTimeAllowance = 540
        let container = CKContainer(identifier: CloudTemplateCodec.containerID)
        let database = container.privateCloudDatabase
        guard try await container.accountStatus() == .available else {
            throw Failure(detail: "The iPhone needs an available iCloud account for live CloudKit checks.")
        }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TallyCloudVerification", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Recover only manifests owned by this harness after an interrupted prior run, never arbitrary zones/subscriptions.
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let prior = try JSONDecoder().decode(Run.self, from: Data(contentsOf: file))
            try await cleanRemote(prior, database: database)
            try? FileManager.default.removeItem(at: root.appendingPathComponent(prior.zoneName, isDirectory: true))
            try FileManager.default.removeItem(at: file)
        }
        let run = Run(zoneName: prefix + UUID().uuidString)
        let manifest = root.appendingPathComponent(run.zoneName).appendingPathExtension("json")
        let folder = root.appendingPathComponent(run.zoneName, isDirectory: true)
        try JSONEncoder().encode(run).write(to: manifest, options: .atomic)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var scenarioError: Error?
        do { try await scenario(run, folder: folder, database: database) }
        catch { scenarioError = error }
        for client in clients { await stop(client) }
        clients.removeAll()
        do {
            try await cleanRemote(run, database: database)
            try FileManager.default.removeItem(at: folder)
            try FileManager.default.removeItem(at: manifest)
            try FileManager.default.removeItem(at: root)
            checkpoint("SCRATCH_ZONE_AND_SUBSCRIPTIONS_REMOVED")
        } catch {
            // Keep the manifest if cleanup fails so the next opt-in run can remove these exact owned resources.
            XCTFail("Scratch cleanup incomplete; retained the owned recovery manifest: \(error.localizedDescription)")
        }
        let attachment = XCTAttachment(string: checkpoints.joined(separator: "\n"))
        attachment.name = "Live CloudKit checkpoints (synthetic data only)"; attachment.lifetime = .keepAlways
        add(attachment)
        if let scenarioError { throw scenarioError }
        #endif
    }

    private func scenario(_ run: Run, folder: URL, database: CKDatabase) async throws {
        let zone = CKRecordZone.ID(zoneName: run.zoneName)
        // Named subscriptions prevent CKSyncEngine from adopting or changing a subscription used by the real library.
        for id in run.subscriptions {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            let info = CKSubscription.NotificationInfo(); info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
        }
        checkpoint("ACCOUNT_AND_OWNED_SUBSCRIPTIONS_READY")
        var a = try client("A", run: run, folder: folder)
        let b = try client("B", run: run, folder: folder)
        var draft = DrinkDraft()
        draft.name = "Synthetic cloud meal"; draft.brand = "Live verification"
        draft.size = "1 serving"; draft.amount = "330"; draft.category = .meal; draft.servingStyle = .bottle
        draft.notes = "Synthetic verification only"; draft.isFavourite = true
        draft.values[.caffeine] = "0"; draft.values[.calories] = "250"; draft.values[.carbohydrates] = "30"
        draft.values[.protein] = "12"; draft.values[.totalFat] = "4"; draft.values[.saturatedFat] = "1"; draft.values[.fibre] = "5"
        draft.estimated = [.caffeine, .protein]
        var original = try DrinkLibrary.save(draft, in: a.context)
        let originalID = original.id
        let expected = SavedDrinkRecord(original)
        let snapshot = try DrinkExportService.export([original])
        let snapshotURL = folder.appendingPathComponent("Library.json")
        try snapshot.write(to: snapshotURL, options: .atomic)
        await a.sync.enable(); try await exchange(a)
        let server = try await database.record(for: CloudTemplateCodec.recordID(originalID, zoneID: zone))
        XCTAssertEqual(try CloudTemplateCodec.change(from: server, zoneID: zone).template, expected)
        await b.sync.enable(); try await exchange(b)
        var peer = try item(originalID, in: b)
        XCTAssertEqual(SavedDrinkRecord(peer), expected)
        XCTAssertNil(peer.sugarG); XCTAssertEqual(peer.caffeineMg, 0); XCTAssertEqual(peer.nutrition.estimated, [.caffeine, .protein])
        for _ in 0..<2 { try await exchange(a); try await exchange(b) }
        XCTAssertEqual(try items(b).count, 1)
        checkpoint("CREATE_ASSET_OPTIONAL_ZERO_ESTIMATES_AND_IDEMPOTENCY")

        // Synthetic local usage stays local even while every editable template field is transferred.
        peer.timesLogged = 7; peer.lastLoggedAt = Date(timeIntervalSince1970: 1_700_000_000); try b.context.save()
        var edited = DrinkDraft(drink: original); edited.name = "Edited synthetic meal"; edited.values[.calories] = "263"
        original = try DrinkLibrary.save(edited, editing: original, in: a.context)
        try DrinkLibrary.toggleFavourite(original, in: a.context)
        try await exchange(a); try await exchange(b)
        peer = try item(originalID, in: b)
        XCTAssertEqual(peer.name, original.name); XCTAssertFalse(peer.isFavourite)
        XCTAssertEqual(peer.caloriesKcal, 263); XCTAssertEqual(peer.timesLogged, 7); XCTAssertNotNil(peer.lastLoggedAt)
        let remote = try await database.record(for: CloudTemplateCodec.recordID(originalID, zoneID: zone))
        let payload = try XCTUnwrap((remote["template"] as? CKAsset)?.fileURL)
        let text = try String(contentsOf: payload, encoding: .utf8)
        XCTAssertFalse(text.contains("timesLogged")); XCTAssertFalse(text.contains("lastLoggedAt"))
        checkpoint("EDIT_FAVOURITE_AND_USAGE_BOUNDARY")

        let restoredData = try DrinkExportService.readFile(snapshotURL)
        XCTAssertEqual(try DrinkExportService.importDrinks(restoredData, into: a.context).imported, 0)
        XCTAssertEqual(try DrinkExportService.importDrinks(restoredData, into: a.context).imported, 0)
        XCTAssertEqual(try DrinkExportService.importDrinks(restoredData, into: a.context, mode: .restoreCopies).imported, 1)
        let copy = try XCTUnwrap(items(a).first { $0.id != originalID })
        XCTAssertEqual(copy.name, expected.name); XCTAssertEqual(copy.timesLogged, 0); XCTAssertNil(copy.lastLoggedAt)
        XCTAssertEqual(try item(originalID, in: a).name, "Edited synthetic meal")
        try await exchange(a); try await exchange(b)
        XCTAssertEqual(try items(b).count, 2)
        checkpoint("JSON_READ_IMPORT_IDEMPOTENCY_AND_RESTORE_AS_COPIES")

        await stop(a)
        var paused = DrinkDraft(); paused.name = "Queued while paused"; paused.values[.protein] = "9"
        let queuedID = try DrinkLibrary.save(paused, in: a.context).id
        a = try client("A", run: run, folder: folder)
        XCTAssertTrue(try XCTUnwrap(LibrarySyncStore.state(for: queuedID, in: a.context)).needsUpload)
        await a.sync.enable(); try await exchange(a); try await exchange(b)
        XCTAssertEqual(try item(queuedID, in: b).proteinG, 9)
        checkpoint("PAUSED_OUTBOX_REOPEN_AND_LIVE_RECONNECT")

        // Keep B's old change tag, stage its earlier edit first, then submit it after A's later server revision.
        var older = try DrinkDraft(drink: item(originalID, in: b)); older.name = "Earlier conflict edit"
        _ = try DrinkLibrary.save(older, editing: item(originalID, in: b), in: b.context)
        var later = try DrinkDraft(drink: item(originalID, in: a)); later.name = "Later server winner"
        _ = try DrinkLibrary.save(later, editing: item(originalID, in: a), in: a.context)
        try await exchange(a)
        try await directSend(b)
        XCTAssertEqual(try item(originalID, in: b).name, "Later server winner")
        checkpoint("STALE_UPLOAD_SERVER_REVISION_WINS")

        // Reverse the ordering: B's later local edit must survive the rejected save and retry with the server's tag.
        var first = try DrinkDraft(drink: item(originalID, in: a)); first.name = "Earlier server revision"
        _ = try DrinkLibrary.save(first, editing: item(originalID, in: a), in: a.context)
        var last = try DrinkDraft(drink: item(originalID, in: b)); last.name = "Later local winner"
        _ = try DrinkLibrary.save(last, editing: item(originalID, in: b), in: b.context)
        try await exchange(a)
        try await directSend(b)
        try await exchange(a)
        XCTAssertEqual(try item(originalID, in: a).name, "Later local winner")
        checkpoint("STALE_UPLOAD_LOCAL_REVISION_RETRIES_AND_WINS")

        var stale = try DrinkDraft(drink: item(originalID, in: b)); stale.name = "Stale edit before deletion"
        _ = try DrinkLibrary.save(stale, editing: item(originalID, in: b), in: b.context)
        try DrinkLibrary.delete(item(originalID, in: a), in: a.context)
        try await exchange(a); try await directSend(b)
        XCTAssertFalse(try items(b).contains { $0.id == originalID })
        let deleted = try await database.record(for: CloudTemplateCodec.recordID(originalID, zoneID: zone))
        XCTAssertTrue(try CloudTemplateCodec.change(from: deleted, zoneID: zone).isDeleted)
        let c = try client("C", run: run, folder: folder)
        await c.sync.enable(); try await exchange(c)
        XCTAssertEqual(Set(try items(c).map(\.id)), Set(try items(b).map(\.id)))
        XCTAssertTrue(try items(c).allSatisfy { $0.timesLogged == 0 && $0.lastLoggedAt == nil })
        checkpoint("DELETE_VERSUS_STALE_EDIT_AND_FRESH_CLIENT_RECOVERY")

        // This is the uniquely owned scratch zone, never the user's TallyLibrary zone.
        _ = try await database.deleteRecordZone(withID: zone)
        await b.sync.syncNow()
        XCTAssertFalse(b.sync.enabled); XCTAssertEqual(try items(b).count, 2)
        do { _ = try await database.recordZone(for: zone); XCTFail("Removed scratch zone was silently recreated") }
        catch let error as CKError { XCTAssertTrue([CKError.Code.zoneNotFound, .userDeletedZone, .unknownItem].contains(error.code)) }
        await b.sync.enable(); try await exchange(b)
        _ = try await database.record(for: CloudTemplateCodec.recordID(queuedID, zoneID: zone))
        checkpoint("REMOTE_ZONE_REMOVAL_PAUSE_AND_EXPLICIT_RECONNECT")
    }

    private func client(_ label: String, run: Run, folder: URL) throws -> Client {
        let store = try LibraryStore.container(configuration: ModelConfiguration(url: folder.appendingPathComponent(label + ".store"), cloudKitDatabase: .none))
        store.mainContext.autosaveEnabled = false
        let sync = try LibrarySyncManager(context: store.mainContext, zoneID: CKRecordZone.ID(zoneName: run.zoneName),
                                          assetDirectory: folder.appendingPathComponent(label + "-assets", isDirectory: true),
                                          automaticallySync: false, subscriptionID: run.zoneName + "-" + label)
        let value = Client(label: label, store: store, sync: sync); clients.append(value); return value
    }
    private func items(_ client: Client) throws -> [SavedDrink] { try client.context.fetch(FetchDescriptor<SavedDrink>()) }
    private func item(_ id: UUID, in client: Client) throws -> SavedDrink {
        try XCTUnwrap(items(client).first { $0.id == id })
    }
    private func exchange(_ client: Client) async throws {
        for _ in 0..<3 {
            await client.sync.syncNow()
            if let error = client.sync.errorMessage { throw Failure(detail: "\(client.label) sync failed: \(error)") }
            guard client.sync.enabled else { throw Failure(detail: "\(client.label) unexpectedly paused") }
            if try LibrarySyncStore.pending(in: client.context).isEmpty { return }
        }
        throw Failure(detail: "\(client.label) still has pending changes after three exchanges")
    }
    private func directSend(_ client: Client) async throws {
        client.sync.configuration.enabled = true; try client.context.save()
        await client.sync.startIfNeeded()
        for _ in 0..<3 {
            _ = try XCTUnwrap(client.sync.engine)
            try await client.sync.sendPendingChanges()
            if let error = client.sync.errorMessage { throw Failure(detail: "\(client.label) direct send failed: \(error)") }
            if try LibrarySyncStore.pending(in: client.context).isEmpty { return }
        }
        throw Failure(detail: "\(client.label) conflict did not settle")
    }
    private func stop(_ client: Client) async {
        let active = client.sync.engine
        client.sync.disable()
        if let active { await active.cancelOperations() }
    }
    private func checkpoint(_ name: String) { checkpoints.append(name); print("TALLY_LIVE_CHECK: \(name)") }
    private func cleanRemote(_ run: Run, database: CKDatabase) async throws {
        guard run.zoneName.hasPrefix(prefix), UUID(uuidString: String(run.zoneName.dropFirst(prefix.count))) != nil,
              run.zoneName != CloudTemplateCodec.zoneID.zoneName else { throw Failure(detail: "Refusing cleanup of an unowned CloudKit zone") }
        var errors: [Error] = []
        for id in run.subscriptions {
            do { _ = try await database.deleteSubscription(withID: id) }
            catch let error as CKError where error.code == .unknownItem { }
            catch { errors.append(error) }
        }
        let zone = CKRecordZone.ID(zoneName: run.zoneName)
        do { _ = try await database.deleteRecordZone(withID: zone) }
        catch let error as CKError where [.zoneNotFound, .userDeletedZone, .unknownItem].contains(error.code) { }
        catch { errors.append(error) }
        if let error = errors.first { throw error }
    }
}
