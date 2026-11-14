import Foundation
import SwiftData
import CloudKit

/// Every callback is scoped to the active engine. Detached/account-changed sessions cannot apply late data.
extension LibrarySyncManager {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, enabled else { return }
        do {
            switch event {
            case let .stateUpdate(update):
                configuration.engineState = try JSONEncoder().encode(update.stateSerialization)
                try context.save()
            case let .accountChange(change):
                switch change.changeType {
                case let .signIn(user):
                    if user.recordName != configuration.accountID { pauseForAccountChange(user.recordName) }
                case .signOut: pauseForAccountChange(nil)
                case let .switchAccounts(_, current): pauseForAccountChange(current.recordName)
                @unknown default: pauseForAccountChange(nil)
                }
            case let .fetchedRecordZoneChanges(changes):
                let account = try await availableAccountID()
                guard engine === syncEngine, enabled else { return }
                guard account == configuration.accountID else { pauseForAccountChange(account); return }
                // Decode/validate the complete batch before mutating persistence or checkpointing its progress.
                let records = try changes.modifications.filter { $0.record.recordType == CloudTemplateCodec.recordType }.map {
                    (try CloudTemplateCodec.change(from: $0.record, zoneID: zoneID), CloudTemplateCodec.systemFields($0.record))
                }
                for (change, fields) in records { try LibrarySyncStore.receive(change, systemFields: fields, in: context) }
                for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                    if let id = UUID(uuidString: deletion.recordID.recordName) { try LibrarySyncStore.receivePhysicalDeletion(id, in: context) }
                }
                try context.save()
                queuePendingChanges()
            case let .sentRecordZoneChanges(changes):
                for record in changes.savedRecords {
                    let change = try CloudTemplateCodec.acknowledgedRevision(from: record, zoneID: zoneID)
                    try LibrarySyncStore.acknowledge(id: change.id, revision: change.revision, systemFields: CloudTemplateCodec.systemFields(record), in: context)
                    // Asset names are validated revision UUIDs, never user-entered paths.
                    try? FileManager.default.removeItem(at: assetDirectory.appendingPathComponent(change.revision).appendingPathExtension("json"))
                }
                var stoppingError: CKError?
                for failure in changes.failedRecordSaves {
                    if failure.error.code == .serverRecordChanged, failure.error.serverRecord != nil {
                        // Conflict errors can contain asset references without downloaded files. Fetch the full current copy.
                        let binding = configuration.accountID
                        let server = try await cloudContainer.privateCloudDatabase.record(for: failure.record.recordID)
                        guard engine === syncEngine, enabled else { return }
                        let account = try await availableAccountID()
                        guard engine === syncEngine, enabled else { return }
                        guard account == binding, configuration.accountID == binding else { pauseForAccountChange(account); return }
                        try LibrarySyncStore.receive(CloudTemplateCodec.change(from: server, zoneID: zoneID), systemFields: CloudTemplateCodec.systemFields(server), in: context)
                    } else if failure.error.code == .unknownItem, let id = UUID(uuidString: failure.record.recordID.recordName) {
                        try LibrarySyncStore.state(for: id, in: context)?.systemFields = nil
                    } else if failure.error.code == .zoneNotFound || failure.error.code == .userDeletedZone {
                        if configuration.zoneEstablished { try pauseForMissingZone(); return }
                        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    } else {
                        show(failure.error)
                        // The engine retries documented transient failures itself. Permanent errors need a user-triggered retry.
                        switch failure.error.code {
                        case .networkUnavailable, .networkFailure, .notAuthenticated, .accountTemporarilyUnavailable, .requestRateLimited, .serviceUnavailable, .zoneBusy: break
                        default: stoppingError = failure.error
                        }
                    }
                }
                try context.save()
                if let stoppingError { detachEngine(); show(stoppingError) }
                else { queuePendingChanges() }
            case let .fetchedDatabaseChanges(changes):
                if configuration.zoneEstablished, changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                    // An established zone disappearing needs consent. A fresh, explicitly reconnected engine can
                    // replay the old deletion before its pending zone creation; do not revoke that new consent.
                    try pauseForMissingZone()
                }
            case let .sentDatabaseChanges(changes):
                if changes.savedZones.contains(where: { $0.zoneID == zoneID }) {
                    configuration.zoneEstablished = true; try context.save()
                }
                if let failure = changes.failedZoneSaves.first { detachEngine(); show(failure.error) }
            case let .didFetchRecordZoneChanges(result):
                if let error = result.error {
                    if error.code == .zoneNotFound || error.code == .userDeletedZone {
                        if configuration.zoneEstablished { try pauseForMissingZone() }
                        // Initial zone creation is already pending; absence is expected before its first successful save.
                    } else { show(error) }
                } else if result.zoneID == zoneID {
                    configuration.zoneEstablished = true; try context.save()
                }
            case .didSendChanges:
                // This timestamp describes a completed exchange, never a guarantee that all devices are current.
                if try LibrarySyncStore.pending(in: context).isEmpty, errorMessage == nil {
                    configuration.lastCompletedAt = .now
                    try context.save()
                }
                if errorMessage == nil { updateStatus() }
            default: break
            }
        } catch { failSafely(error) }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine, enabled else { return nil }
        do {
            let account = try await availableAccountID()
            guard engine === syncEngine, enabled else { return nil }
            guard account == configuration.accountID else { pauseForAccountChange(account); return nil }
            queuePendingChanges()
            let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
            let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
                guard let self else { return nil }
                return await self.recordToUpload(id, engine: syncEngine)
            }
            guard engine === syncEngine, enabled else { return nil }
            return batch
        } catch { show(error); return nil }
    }
    private func recordToUpload(_ id: CKRecord.ID, engine active: CKSyncEngine) -> CKRecord? {
        guard engine === active, enabled, id.zoneID == zoneID, let uuid = UUID(uuidString: id.recordName) else { return nil }
        do {
            guard let row = try LibrarySyncStore.state(for: uuid, in: context), row.needsUpload else {
                active.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
            return try CloudTemplateCodec.record(for: LibrarySyncStore.change(row), systemFields: row.systemFields, assetDirectory: assetDirectory, zoneID: zoneID)
        } catch { failSafely(error); return nil }
    }
    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        .init(scope: .zoneIDs([zoneID]))
    }
}
