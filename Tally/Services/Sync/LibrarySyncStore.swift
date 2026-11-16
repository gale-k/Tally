import Foundation
import SwiftData

/// Only this explicit transfer type crosses the CloudKit boundary. Revision identity makes retries idempotent.
struct CloudTemplateChange: Codable, Equatable, Sendable {
    var version = 1
    var id: UUID
    var modifiedAt: Date
    var revision: String
    var template: SavedDrinkRecord?
    var isDeleted: Bool { template == nil }

    func validate() throws {
        guard version == 1, modifiedAt.timeIntervalSince1970.isFinite, UUID(uuidString: revision) != nil,
              template == nil || template?.id == id else { throw LibrarySyncError.invalidRecord }
        try template?.validate()
    }

    /// Whole-template last-change-wins. Equal timestamps favour deletion, then a stable revision UUID.
    func precedes(_ other: Self) -> Bool {
        if modifiedAt != other.modifiedAt { return modifiedAt < other.modifiedAt }
        if isDeleted != other.isDeleted { return !isDeleted }
        return revision < other.revision
    }
}

enum LibrarySyncError: LocalizedError {
    case invalidRecord, accountChanged, noAccount, unavailable, pendingEdits
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "An iCloud template has an unsupported or invalid format. Your local library has been kept. Update Tally and try again."
        case .accountChanged: "The iCloud account changed. Sync is paused and your local library is safe. Switch back, or explicitly connect this library to the current account."
        case .noAccount: "Sign into iCloud in Settings and allow Tally to use iCloud. Your local library is still available."
        case .unavailable: "iCloud is unavailable right now. Your library stays available on this device. Try again later."
        case .pendingEdits: "Finish saving your current changes before connecting iCloud."
        }
    }
}

/// Persistence/merge logic is independent of CKSyncEngine, so offline and conflict paths can be tested locally.
@MainActor
enum LibrarySyncStore {
    static func state(for id: UUID, in context: ModelContext) throws -> TemplateSyncState? {
        var request = FetchDescriptor<TemplateSyncState>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    static func configuration(in context: ModelContext) throws -> LibrarySyncConfiguration {
        if let existing = try context.fetch(FetchDescriptor<LibrarySyncConfiguration>()).first { return existing }
        let result = LibrarySyncConfiguration(); context.insert(result); try context.save()
        return result
    }
    static func pending(in context: ModelContext) throws -> [TemplateSyncState] {
        try context.fetch(FetchDescriptor<TemplateSyncState>(predicate: #Predicate { $0.needsUpload }))
    }
    static func change(_ state: TemplateSyncState) throws -> CloudTemplateChange {
        let item = try state.payload.map { try JSONDecoder().decode(SavedDrinkRecord.self, from: $0) }
        let result = CloudTemplateChange(id: state.id, modifiedAt: state.modifiedAt, revision: state.revision, template: state.tombstone ? nil : item)
        guard state.tombstone || item != nil else { throw LibrarySyncError.invalidRecord }
        try result.validate()
        return result
    }
    static func stage(_ item: SavedDrink, in context: ModelContext, now: Date = .now) throws {
        let row = try existingOrNew(item.id, in: context)
        let template = SavedDrinkRecord(item)
        try template.validate()
        row.payload = try JSONEncoder().encode(template)
        markChanged(row, deleted: false, now: now)
    }
    static func stageDeletion(_ id: UUID, in context: ModelContext, now: Date = .now) throws {
        let row = try existingOrNew(id, in: context)
        row.payload = nil
        markChanged(row, deleted: true, now: now)
    }
    private static func existingOrNew(_ id: UUID, in context: ModelContext) throws -> TemplateSyncState {
        if let row = try state(for: id, in: context) { return row }
        let row = TemplateSyncState(id: id, modifiedAt: .distantPast); context.insert(row); return row
    }
    private static func markChanged(_ row: TemplateSyncState, deleted: Bool, now: Date) {
        // A local edit after a remote revision must sort later even if the device clock moved backwards.
        row.modifiedAt = max(now, row.modifiedAt.addingTimeInterval(0.001))
        row.revision = UUID().uuidString; row.tombstone = deleted; row.needsUpload = true
    }

    static func connect(accountID: String, configuration: LibrarySyncConfiguration, allowAccountChange: Bool,
                        in context: ModelContext) throws {
        guard !context.hasChanges else { throw LibrarySyncError.pendingEdits }
        let changed = configuration.accountID != nil && configuration.accountID != accountID
        guard !changed || allowAccountChange else { throw LibrarySyncError.accountChanged }
        do {
            let items = try context.fetch(FetchDescriptor<SavedDrink>())
            if changed {
                // Never send the previous account's tombstones or change tags to a different private database.
                for row in try context.fetch(FetchDescriptor<TemplateSyncState>()) { context.delete(row) }
                configuration.engineState = nil; configuration.lastCompletedAt = nil; configuration.zoneEstablished = false
            }
            for item in items {
                if changed { try stage(item, in: context, now: item.updatedAt) }
                else if try state(for: item.id, in: context) == nil { try stage(item, in: context, now: item.updatedAt) }
            }
            configuration.accountID = accountID; configuration.enabled = true
            try context.save()
        } catch { context.rollback(); throw error }
    }

    /// Fetches update templates without touching this device's convenience usage counters or HealthKit.
    static func receive(_ incoming: CloudTemplateChange, systemFields: Data?, in context: ModelContext) throws {
        try incoming.validate()
        let row = try existingOrNew(incoming.id, in: context)
        let local = row.payload == nil && !row.tombstone ? nil : try change(row)
        row.systemFields = systemFields
        if let local, incoming.revision != local.revision, incoming.precedes(local) {
            row.needsUpload = true
            return
        }
        if let record = incoming.template {
            let identifier = incoming.id
            var request = FetchDescriptor<SavedDrink>(predicate: #Predicate { $0.id == identifier })
            request.fetchLimit = 1
            if let existing = try context.fetch(request).first {
                apply(record, to: existing)
            } else { context.insert(record.makeDrink()) }
        } else {
            let id = incoming.id
            for item in try context.fetch(FetchDescriptor<SavedDrink>(predicate: #Predicate { $0.id == id })) { context.delete(item) }
        }
        row.payload = try incoming.template.map { try JSONEncoder().encode($0) }
        row.modifiedAt = incoming.modifiedAt; row.revision = incoming.revision
        row.tombstone = incoming.isDeleted; row.needsUpload = false
    }

    static func acknowledge(id: UUID, revision: String, systemFields: Data, in context: ModelContext) throws {
        guard let row = try state(for: id, in: context) else { return }
        row.systemFields = systemFields
        // An edit made while an earlier upload was in flight must remain pending.
        if row.revision == revision { row.needsUpload = false }
    }
    static func receivePhysicalDeletion(_ id: UUID, in context: ModelContext) throws {
        if let row = try state(for: id, in: context), row.needsUpload { row.systemFields = nil; return }
        for item in try context.fetch(FetchDescriptor<SavedDrink>(predicate: #Predicate { $0.id == id })) { context.delete(item) }
        let row = try existingOrNew(id, in: context)
        row.payload = nil; row.tombstone = true; row.needsUpload = false; row.systemFields = nil
    }
    private static func apply(_ record: SavedDrinkRecord, to item: SavedDrink) {
        item.name = record.name; item.brandOrLocation = record.brandOrLocation; item.size = record.size
        // Apply both optional fields so a remote unit switch clears the previous measurement locally.
        item.volumeMl = record.volumeMl; item.weightG = record.weightG
        item.categoryRaw = record.category.rawValue; item.servingStyleRaw = record.servingStyle.rawValue
        item.nutrition = record.nutrition; item.notes = record.notes; item.isFavourite = record.isFavourite
        // A payload from an older client has no archive field and represents an active template.
        item.isArchived = record.isArchived ?? false
        item.createdAt = record.createdAt; item.updatedAt = record.updatedAt
    }
}
