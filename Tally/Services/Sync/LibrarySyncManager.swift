import Foundation
import SwiftData
import CloudKit
import Observation
import UIKit
import Combine

/// Optional template syncing. The existing local store remains usable without a network or iCloud account.
@MainActor @Observable
final class LibrarySyncManager: CKSyncEngineDelegate {
    let context: ModelContext
    let configuration: LibrarySyncConfiguration
    let allowsCloudAccess: Bool
    // Production defaults are unchanged; isolated live checks supply their own zone, assets and subscription.
    let zoneID: CKRecordZone.ID
    let assetDirectory: URL
    private let automaticallySync: Bool
    private let subscriptionID: CKSubscription.ID?
    @ObservationIgnored var engine: CKSyncEngine?
    @ObservationIgnored private var accountObserver: AnyCancellable?
    @ObservationIgnored private var saveObserver: AnyCancellable?
    @ObservationIgnored private var starting = false
    private var sessionPaused = false
    var status = "Off"
    var message = "Your library is available on this device."
    var errorMessage: String?
    var isBusy = false
    var pendingCount = 0
    var pendingAccountID: String?
    var enabled: Bool { configuration.enabled && !sessionPaused }
    var lastCompletedAt: Date? { configuration.lastCompletedAt }
    var cloudContainer: CKContainer { CKContainer(identifier: CloudTemplateCodec.containerID) }

    init(context: ModelContext, allowsCloudAccess: Bool = true, zoneID: CKRecordZone.ID? = nil,
         assetDirectory: URL? = nil, automaticallySync: Bool = true, subscriptionID: CKSubscription.ID? = nil) throws {
        self.context = context; self.allowsCloudAccess = allowsCloudAccess
        self.zoneID = zoneID ?? CloudTemplateCodec.zoneID
        self.assetDirectory = assetDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TallyCloudAssets", isDirectory: true)
        self.automaticallySync = automaticallySync; self.subscriptionID = subscriptionID
        configuration = try LibrarySyncStore.configuration(in: context)
        if configuration.enabled { status = "Waiting for iCloud" }
        // Save notifications carry no payload into CloudKit; only pending template DTOs are subsequently read.
        saveObserver = NotificationCenter.default.publisher(for: ModelContext.didSave).sink { [weak self] _ in
            Task { @MainActor in self?.queuePendingChanges() }
        }
        accountObserver = NotificationCenter.default.publisher(for: .CKAccountChanged).sink { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount() }
        }
    }
    func refreshAccount() async {
        guard enabled else { return }
        await startIfNeeded()
        if engine != nil { await syncNow() }
    }
    func startIfNeeded() async {
        guard enabled, engine == nil, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let account = try await availableAccountID()
            guard enabled else { return }
            guard account == configuration.accountID else { pauseForAccountChange(account); return }
            try startEngine()
        } catch { show(error) }
    }
    func enable(confirmingAccountID: String? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let account = try await availableAccountID()
            let different = configuration.accountID != nil && configuration.accountID != account
            if different && confirmingAccountID != account { pauseForAccountChange(account); return }
            detachEngine()
            try LibrarySyncStore.connect(accountID: account, configuration: configuration, allowAccountChange: different, in: context)
            sessionPaused = false
            pendingAccountID = nil
            try startEngine()
        } catch { show(error) }
        // Manual exchanges fetch first; stable revisions also resolve conflicts with automatically scheduled uploads.
        if engine != nil { await performSync() }
    }
    func disable() {
        // Honour the opt-out for this process even if persisting the preference fails.
        sessionPaused = true
        detachEngine()
        do { configuration.enabled = false; try context.save() }
        catch { context.rollback(); show(error); return }
        status = "Off"; message = "Local templates and the existing iCloud library are kept. Changes will wait until you reconnect."
        errorMessage = nil
        try? FileManager.default.removeItem(at: assetDirectory)
    }
    func syncNow() async {
        guard enabled, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        if engine == nil { await startIfNeeded() }
        await performSync()
    }
    private func performSync() async {
        guard let active = engine else { return }
        do {
            let account = try await availableAccountID()
            guard engine === active, enabled else { return }
            guard account == configuration.accountID else { pauseForAccountChange(account); return }
            status = "Syncing"; errorMessage = nil
            do { try await active.fetchChanges(.init(scope: .zoneIDs([zoneID]))) }
            catch {
                // On first opt-in the zone may not exist yet. Let the already-pending zone creation run next.
                guard let cloud = error as? CKError, !configuration.zoneEstablished,
                      cloud.code == .zoneNotFound || cloud.code == .userDeletedZone else { throw error }
            }
            guard engine === active, enabled else { return }
            queuePendingChanges()
            try await sendPendingChanges()
            guard engine === active, enabled else { return }
            if errorMessage == nil { updateStatus() }
        } catch { if engine === active { show(error) } }
    }
    /// CKSyncEngine reports record conflicts to the delegate and also throws them from sendChanges.
    /// Re-send the delegate's resolved local winner, or finish quietly when the server winner cleared the outbox.
    func sendPendingChanges() async throws {
        guard let active = engine, enabled else { return }
        for _ in 0..<3 {
            do { try await active.sendChanges(); return }
            catch {
                guard engine === active, enabled else { return }
                guard errorMessage == nil, CloudSyncFailure.isRecordConflict(error) else { throw error }
                if try LibrarySyncStore.pending(in: context).isEmpty { return }
                queuePendingChanges()
            }
        }
        // Continuous concurrent edits remain visibly pending; automatic sync or a later manual exchange can retry.
        updateStatus()
    }

    func availableAccountID() async throws -> String {
        guard allowsCloudAccess else { throw LibrarySyncError.unavailable }
        let container = cloudContainer
        switch try await container.accountStatus() {
        case .available: return try await container.userRecordID().recordName
        case .noAccount: throw LibrarySyncError.noAccount
        default: throw LibrarySyncError.unavailable
        }
    }
    private func startEngine() throws {
        let state: CKSyncEngine.State.Serialization?
        do { state = try configuration.engineState.map { try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) } }
        catch {
            // A damaged opaque checkpoint can be rebuilt by refetching stable UUIDs; never reset the template store.
            configuration.engineState = nil; try context.save(); state = nil
        }
        var config = CKSyncEngine.Configuration(database: cloudContainer.privateCloudDatabase, stateSerialization: state, delegate: self)
        config.automaticallySync = automaticallySync; config.subscriptionID = subscriptionID
        engine = CKSyncEngine(config)
        // The SDK's sync engine requires silent remote notifications; no alert-notification permission is requested.
        UIApplication.shared.registerForRemoteNotifications()
        // Recreating an established zone on every launch could hide a deliberate remote library removal.
        if !configuration.zoneEstablished {
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        queuePendingChanges()
        updateStatus()
    }
    func queuePendingChanges() {
        do {
            let pending = try LibrarySyncStore.pending(in: context)
            pendingCount = pending.count
            guard enabled, let engine else { return }
            // A new local edit must stop advertising an empty outbox before the next engine exchange begins.
            if pendingCount > 0, !isBusy, errorMessage == nil {
                status = "Changes pending"
                message = "Local changes are saved. iCloud will retry when conditions allow, or use Sync Now."
            }
            let registered = Set(engine.state.pendingRecordZoneChanges)
            let changes = pending.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CloudTemplateCodec.recordID($0.id, zoneID: zoneID)) }
            let missing = changes.filter { !registered.contains($0) }
            if !missing.isEmpty { engine.state.add(pendingRecordZoneChanges: missing) }
        } catch { failSafely(error) }
    }
    func updateStatus() {
        guard enabled else { return }
        queuePendingChanges()
        guard engine != nil else { return }
        if pendingCount > 0 {
            status = "Changes pending"; message = "Local changes are saved. iCloud will retry when conditions allow, or use Sync Now."
        } else {
            status = "Connected"; message = "No local template changes are waiting to upload. Other devices may still have changes to send."
        }
    }
    func pauseForAccountChange(_ newAccountID: String?) {
        sessionPaused = true
        detachEngine()
        do { configuration.enabled = false; try context.save() }
        catch { context.rollback(); show(error); return }
        pendingAccountID = newAccountID
        status = "Account needs attention"; message = LibrarySyncError.accountChanged.localizedDescription
        errorMessage = nil
    }
    func pauseForMissingZone() throws {
        pauseForAccountChange(configuration.accountID)
        message = "The iCloud library was removed. Local templates are kept. Reconnect explicitly to publish them again."
        configuration.enabled = false; configuration.engineState = nil; configuration.zoneEstablished = false
        for row in try context.fetch(FetchDescriptor<TemplateSyncState>()) { row.systemFields = nil; row.needsUpload = true }
        try context.save()
    }

    func detachEngine() {
        let previous = engine
        engine = nil
        // Cancellation must happen outside a delegate event, which the SDK delivers serially.
        if let previous { Task { await previous.cancelOperations() } }
    }
    func failSafely(_ error: Error) {
        detachEngine()
        context.rollback()
        show(error)
    }
    func show(_ error: Error) {
        status = "Needs attention"
        if let cloud = error as? CKError {
            switch cloud.code {
            case .notAuthenticated: errorMessage = LibrarySyncError.noAccount.localizedDescription
            case .quotaExceeded: errorMessage = "iCloud storage is full. Local changes are safe and still waiting. Free some iCloud space and retry."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable:
                errorMessage = "iCloud couldn’t be reached. Local changes are safe and will retry when conditions allow."
            default: errorMessage = "iCloud couldn’t finish syncing. Your local library is safe. Check iCloud access for Tally and try again."
            }
        } else { errorMessage = error.localizedDescription }
        message = "Your saved library remains available on this device."
    }
}
