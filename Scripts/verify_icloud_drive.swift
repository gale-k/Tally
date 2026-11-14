import Foundation
import SwiftData

/// Uses only a newly created synthetic snapshot; it never opens another iCloud Drive file.
@main @MainActor struct DriveCheck {
    struct Failure: LocalizedError { let errorDescription: String? }
    @MainActor static func main() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--allow-live-drive") else {
            fputs("Pass --allow-live-drive to allow a temporary synthetic iCloud Drive snapshot.\n", stderr)
            exit(2)
        }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let file = folder.appendingPathComponent("TallyCloudVerification-" + UUID().uuidString).appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: folder.path), !FileManager.default.fileExists(atPath: file.path) else {
            throw Failure(errorDescription: "iCloud Drive is unavailable or the scratch filename already exists")
        }
        let sample = SavedDrink(name: "Synthetic backup check", category: .meal, nutrition: .init(caffeine: 0, calories: 250, protein: 12, estimated: [.protein]), isFavourite: true)
        let data = try DrinkExportService.export([sample])
        print("TALLY_DRIVE_OWNED_SNAPSHOT: " + file.lastPathComponent)
        try data.write(to: file, options: .atomic)
        var failure: Error?
        do {
            try await wait(file, phase: "upload") { $0.isUbiquitousItem == true && $0.ubiquitousItemIsUploaded == true }
            print("TALLY_DRIVE_CHECK: UPLOAD_CONFIRMED")
            try FileManager.default.evictUbiquitousItem(at: file)
            try await wait(file, phase: "eviction") { $0.ubiquitousItemDownloadingStatus == .notDownloaded }
            print("TALLY_DRIVE_CHECK: LOCAL_COPY_EVICTED")
            try FileManager.default.startDownloadingUbiquitousItem(at: file)
            try await wait(file, phase: "download") { $0.ubiquitousItemDownloadingStatus == .current }
            let recovered = try DrinkExportService.readFile(file)
            guard recovered == data else { throw Failure(errorDescription: "Downloaded snapshot differs") }
            let store = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            guard try DrinkExportService.importDrinks(recovered, into: store.mainContext).imported == 1,
                  try DrinkExportService.importDrinks(recovered, into: store.mainContext).imported == 0,
                  try DrinkExportService.importDrinks(recovered, into: store.mainContext, mode: .restoreCopies).imported == 1 else {
                throw Failure(errorDescription: "Downloaded snapshot restoration failed")
            }
            print("TALLY_DRIVE_CHECK: DOWNLOAD_AND_RESTORE_VERIFIED")
        } catch { failure = error }
        try FileManager.default.removeItem(at: file)
        print("TALLY_DRIVE_CHECK: OWNED_SNAPSHOT_REMOVED")
        if let failure { throw failure }
    }
    static func wait(_ file: URL, phase: String, condition: (URLResourceValues) -> Bool) async throws {
        for _ in 0..<45 {
            let current = URL(fileURLWithPath: file.path)
            let values = try current.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey])
            if condition(values) { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw Failure(errorDescription: "iCloud Drive did not confirm \(phase) within 45 seconds")
    }
}
