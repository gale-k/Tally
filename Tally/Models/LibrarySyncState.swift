import Foundation
import SwiftData

/// This local-only outbox commits with template edits. It never contains usage counts or Health history.
@Model
final class TemplateSyncState {
    @Attribute(.unique) var id: UUID
    var payload: Data?
    var modifiedAt: Date
    var revision: String
    // Avoid PersistentModel.isDeleted: this flag describes a synced template deletion, not this row’s lifecycle.
    var tombstone: Bool
    var needsUpload: Bool
    var systemFields: Data?

    init(id: UUID, payload: Data? = nil, modifiedAt: Date = .now, revision: String = UUID().uuidString,
         tombstone: Bool = false, needsUpload: Bool = true) {
        self.id = id; self.payload = payload; self.modifiedAt = modifiedAt; self.revision = revision
        self.tombstone = tombstone; self.needsUpload = needsUpload
    }
}

/// Account binding and engine checkpoints stay on this device, including while sync is disabled.
@Model
final class LibrarySyncConfiguration {
    @Attribute(.unique) var id: String
    var enabled: Bool
    var accountID: String?
    var engineState: Data?
    var zoneEstablished: Bool = false
    var lastCompletedAt: Date?

    init() { id = "library"; enabled = false }
}

/// Additive local entities preserve the original SavedDrink schema and its enforced UUID uniqueness.
@MainActor
enum LibraryStore {
    static func container(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: SavedDrink.self, TemplateSyncState.self, LibrarySyncConfiguration.self, configurations: configuration)
    }
}
