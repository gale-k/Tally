import Foundation
import SwiftData

/// The versioned format contains templates only; usage counts, consumption dates, and Health samples are excluded.
struct SavedDrinkRecord: Codable {
    var id: UUID
    var name: String
    var brandOrLocation: String?
    var size: String?
    var volumeMl: Double?
    var category: DrinkCategory
    var servingStyle: ServingStyle
    var nutrition: NutritionValues
    var notes: String?
    var isFavourite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(_ drink: SavedDrink) {
        id = drink.id; name = drink.name; brandOrLocation = drink.brandOrLocation; size = drink.size
        volumeMl = drink.volumeMl; category = drink.category; servingStyle = drink.servingStyle
        nutrition = drink.nutrition; notes = drink.notes; isFavourite = drink.isFavourite
        createdAt = drink.createdAt; updatedAt = drink.updatedAt
    }
    func validate() throws {
        // Match the editor's accepted text domain; the file-size bound already limits import resources.
        guard DrinkDraft.optionalText(name) != nil, createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite else { throw LibraryTransferError.invalidRecord }
        if let volumeMl, !volumeMl.isFinite || volumeMl <= 0 || volumeMl > 100_000 { throw DrinkValidationError.invalidVolume }
        try nutrition.validate()
    }
    func makeDrink() -> SavedDrink {
        SavedDrink(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), brandOrLocation: brandOrLocation,
                   size: size, volumeMl: volumeMl, category: category, servingStyle: servingStyle,
                   nutrition: nutrition, notes: notes, isFavourite: isFavourite, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct SavedDrinkBackup: Codable {
    var version = 1
    var drinks: [SavedDrinkRecord]
}

struct DrinkImportReport {
    var imported: Int
    var skipped: Int
    var message: String { "Imported \(imported) \(imported == 1 ? "item" : "items"). \(skipped) already in your library. Existing items were kept unchanged." }
}

enum LibraryTransferError: LocalizedError {
    case tooLarge, unsupportedVersion, duplicateIdentifiers, invalidRecord, pendingChanges
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose a Tally JSON library smaller than 5 MB with no more than 5,000 items."
        case .unsupportedVersion: "This library uses an unsupported format version. Update Tally or use a version 1 export."
        case .duplicateIdentifiers: "The file contains duplicate item identifiers. No items were imported."
        case .invalidRecord: "An item has missing or invalid information. No items were imported."
        case .pendingChanges: "Finish saving your current changes before importing a library."
        }
    }
}

@MainActor
enum DrinkExportService {
    static let maximumBytes = 5 * 1_024 * 1_024
    static func export(_ drinks: [SavedDrink]) throws -> Data {
        let backup = SavedDrinkBackup(drinks: drinks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(SavedDrinkRecord.init))
        for record in backup.drinks { try record.validate() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        guard data.count <= maximumBytes, drinks.count <= 5_000 else { throw LibraryTransferError.tooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> [SavedDrinkRecord] {
        guard data.count <= maximumBytes else { throw LibraryTransferError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(SavedDrinkBackup.self, from: data)
        guard backup.version == 1 else { throw LibraryTransferError.unsupportedVersion }
        guard backup.drinks.count <= 5_000 else { throw LibraryTransferError.tooLarge }
        guard Set(backup.drinks.map(\.id)).count == backup.drinks.count else { throw LibraryTransferError.duplicateIdentifiers }
        for record in backup.drinks { try record.validate() }
        return backup.drinks
    }
    static func readFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw LibraryTransferError.tooLarge }
        return data
    }
    static func importDrinks(_ data: Data, into context: ModelContext) throws -> DrinkImportReport {
        // Validate the complete file before inserting anything, then persist additions as one batch.
        let records = try decode(data)
        guard !context.hasChanges else { throw LibraryTransferError.pendingChanges }
        let existing = Set(try context.fetch(FetchDescriptor<SavedDrink>()).map(\.id))
        let additions = records.filter { !existing.contains($0.id) }
        do {
            for record in additions { context.insert(record.makeDrink()) }
            try context.save()
        } catch { context.rollback(); throw error }
        return DrinkImportReport(imported: additions.count, skipped: records.count - additions.count)
    }
}
