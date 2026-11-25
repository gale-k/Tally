import SwiftUI
import SwiftData

/// Sync is opt-in and is clearly separate from an independent snapshot backup.
struct CloudLibrarySection: View {
    @Environment(LibrarySyncManager.self) private var sync
    @Query private var items: [SavedDrink]
    @State private var enabling = false
    @State private var reconnecting = false

    var body: some View {
        Section {
            HStack {
                LabeledContent("Library sync", value: sync.status)
                if sync.isBusy { ProgressView().accessibilityLabel("Syncing saved templates") }
            }
            Text(sync.message).font(.footnote).foregroundStyle(.secondary)
            if let error = sync.errorMessage { Label(error, systemImage: "exclamationmark.icloud").font(.footnote) }
            if sync.enabled {
                LabeledContent("Templates waiting to upload", value: sync.pendingCount.formatted())
                if let date = sync.lastCompletedAt { LabeledContent("Last completed exchange", value: date.formatted(date: .abbreviated, time: .shortened)) }
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud") { Task { await sync.syncNow() } }.disabled(sync.isBusy)
                Button("Turn Off iCloud Sync") { sync.disable() }
            } else {
                Button("Enable iCloud Sync", systemImage: "icloud") { enabling = true }.disabled(sync.isBusy)
            }
            if sync.pendingAccountID != nil {
                Button("Connect Library to Current Account") { reconnecting = true }.disabled(sync.isBusy)
            }
        } header: { Text("iCloud Library") }
        footer: {
            Text("Optional private iCloud storage for saved templates, including nutrition, recipes, notes and favourites. Usage counts, Health permissions and preferences stay local. Consumption history stays in Apple Health. Sync propagates deletions; it is not an independent backup.")
        }
        .confirmationDialog("Enable iCloud Library Sync?", isPresented: $enabling, titleVisibility: .visible) {
            Button("Enable Sync") { Task { await sync.enable() } }
        } message: {
            Text("Your \(items.count) saved templates will merge with this iCloud account’s library. Changes and deletions can reach your other devices. Apple Health history is excluded. Export a snapshot first if you want a separate recovery copy.")
        }
        .confirmationDialog("Connect to the Current iCloud Account?", isPresented: $reconnecting, titleVisibility: .visible, presenting: sync.pendingAccountID) { accountID in
            Button("Connect and Merge Templates") { Task { await sync.enable(confirmingAccountID: accountID) } }
        } message: { _ in
            Text("This explicitly merges the saved library on this device with the current iCloud account. Remote changes may update these templates. The previous account’s iCloud library is kept. No Health history will be transferred.")
        }
    }
}
