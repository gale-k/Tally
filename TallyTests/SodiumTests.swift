import XCTest
import SwiftData
import HealthKit
@testable import Tally

/// Sodium and label salt share one canonical value throughout entry, persistence, sync, and Health.
@MainActor
final class SodiumTests: XCTestCase {
    func testSaltConvertsToSodiumAndUnitSwitchPreservesAmountAndEstimate() throws {
        var draft = DrinkDraft(); draft.name = "Soup"; draft.sodiumInputUnit = .salt
        draft.values[.sodium] = "1.25"; draft.estimated = [.sodium]
        XCTAssertEqual(try draft.nutrition().sodium, 500)
        try draft.changeSodiumInputUnit(to: .sodium)
        XCTAssertEqual(draft.values[.sodium], "500")
        try draft.changeSodiumInputUnit(to: .salt)
        XCTAssertEqual(draft.values[.sodium], "1.25")
        let item = try draft.makeDrink()
        XCTAssertEqual(item.sodiumMg, 500)
        XCTAssertEqual(item.nutrition.summaryText, "~500 mg sodium")
        let reopened = DrinkDraft(drink: item)
        XCTAssertEqual(reopened.sodiumInputUnit, .sodium)
        XCTAssertEqual(try reopened.nutrition(), item.nutrition)
    }

    func testUnknownZeroLimitsAndLocaleAwareSaltValidation() throws {
        for unit in SodiumInputUnit.allCases {
            var draft = DrinkDraft(); draft.sodiumInputUnit = unit; draft.estimated = [.sodium]
            XCTAssertNil(try draft.nutrition().sodium)
            XCTAssertTrue(try draft.nutrition().estimated.isEmpty)
            draft.values[.sodium] = "0"
            XCTAssertEqual(try draft.nutrition().sodium, 0)
            XCTAssertEqual(try draft.nutrition().knownNutrients, [.sodium])
            draft.values[.sodium] = String(unit.inputLimit)
            XCTAssertEqual(try draft.nutrition().sodium, Nutrient.sodium.inputLimit)
            for invalid in ["-1", "nan", "inf", "1.2.3", String(unit.inputLimit + 1)] {
                draft.values[.sodium] = invalid
                XCTAssertThrowsError(try draft.nutrition()) { error in
                    XCTAssertTrue(error.localizedDescription.contains(unit.title.lowercased()))
                    XCTAssertTrue(error.localizedDescription.contains(unit.unit))
                }
                // A failed conversion must neither discard invalid text nor change its interpretation.
                XCTAssertThrowsError(try draft.changeSodiumInputUnit(to: unit == .salt ? .sodium : .salt))
                XCTAssertEqual(draft.sodiumInputUnit, unit)
                XCTAssertEqual(draft.values[.sodium], invalid)
            }
        }
        let locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(try DrinkDraft.parse("1,25", nutrient: .sodium, locale: locale, sodiumInputUnit: .salt), 500)
        var draft = DrinkDraft(); draft.values[.sodium] = "0,04"
        try draft.changeSodiumInputUnit(to: .salt, locale: locale)
        XCTAssertEqual(try DrinkDraft.parse(draft.values[.sodium]!, nutrient: .sodium, locale: locale, sodiumInputUnit: .salt)!, 0.04, accuracy: 0.0000001)
    }

    func testUnitConversionKeepsBlankZeroAndSmallDecimalInputsReadable() throws {
        for (input, salt) in [("", ""), ("0", "0"), ("1.1", "0.00275"), ("330", "0.825"), ("0.000000001", "0.0000000000025")] {
            var draft = DrinkDraft(); draft.values[.sodium] = input
            try draft.changeSodiumInputUnit(to: .salt, locale: Locale(identifier: "en_GB"))
            XCTAssertEqual(draft.values[.sodium], salt)
            try draft.changeSodiumInputUnit(to: .sodium, locale: Locale(identifier: "en_GB"))
            XCTAssertEqual(draft.values[.sodium], input)
        }
    }

    func testSodiumPersistsAfterDiskReopenEditAndDuplication() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallySodium-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Library.store"), cloudKitDatabase: .none)
        do {
            let writer = try LibraryStore.container(configuration: configuration)
            var draft = DrinkDraft(); draft.name = "Soup"; draft.sodiumInputUnit = .salt
            draft.values[.sodium] = "1.25"; draft.estimated = [.sodium]
            try DrinkLibrary.save(draft, in: writer.mainContext)
        }
        let reader = try LibraryStore.container(configuration: configuration)
        let item = try XCTUnwrap(reader.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
        XCTAssertEqual(item.sodiumMg, 500)
        XCTAssertEqual(item.nutrition.estimated, [.sodium])
        let copy = try DrinkLibrary.duplicate(item, in: reader.mainContext)
        XCTAssertEqual(copy.nutrition, item.nutrition)
        var edited = DrinkDraft(drink: item); edited.values[.sodium] = "0"
        try DrinkLibrary.save(edited, editing: item, in: reader.mainContext)
        XCTAssertEqual(item.sodiumMg, 0)
        XCTAssertEqual(copy.sodiumMg, 500)
    }

    func testSodiumSurvivesSnapshotImportRestoreAndCloudPayload() throws {
        let item = SavedDrink(name: "Soup", nutrition: .init(sodium: 500, estimated: [.sodium]))
        let data = try DrinkExportService.export([item])
        for mode in [LibraryImportMode.addMissing, .restoreCopies] {
            let container = try LibraryStore.container(configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            XCTAssertEqual(try DrinkExportService.importDrinks(data, into: container.mainContext, mode: mode).imported, 1)
            let restored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedDrink>()).first)
            XCTAssertEqual(restored.nutrition, item.nutrition)
            let state = try XCTUnwrap(LibrarySyncStore.state(for: restored.id, in: container.mainContext))
            XCTAssertEqual(try LibrarySyncStore.change(state).template?.nutrition, item.nutrition)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TallySodiumAsset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let change = CloudTemplateChange(id: item.id, modifiedAt: item.updatedAt, revision: UUID().uuidString, template: SavedDrinkRecord(item))
        let record = try CloudTemplateCodec.record(for: change, systemFields: nil, assetDirectory: folder)
        XCTAssertEqual(try CloudTemplateCodec.change(from: record), change)
    }

    func testSaltProducesExactlyOneSodiumSampleWithCorrectMassAndMetadata() throws {
        var draft = DrinkDraft(); draft.sodiumInputUnit = .salt
        draft.values[.sodium] = "1.25"; draft.estimated = [.sodium]
        let event = ConsumptionDraft(name: "Soup", nutrition: try draft.nutrition())
        let samples = try HealthKitStore.makeSamples(for: event)
        XCTAssertEqual(samples.count, 1)
        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.quantityType, HKQuantityType(.dietarySodium))
        XCTAssertEqual(sample.quantity.doubleValue(for: .gramUnit(with: .milli)), 500)
        XCTAssertEqual(sample.quantity.doubleValue(for: .gram()), 0.5, accuracy: 0.00001)
        XCTAssertEqual(sample.metadata?[HealthKitStore.estimatedKey] as? Bool, true)
        XCTAssertEqual(sample.metadata?[HealthKitStore.eventKey] as? String, event.id.uuidString)
        // Zero entered as salt converts to zero sodium and is omitted from a mixed entry.
        draft.values[.sodium] = "0"
        draft.values[.calories] = "100"
        let zeroSalt = ConsumptionDraft(name: "Soup", nutrition: try draft.nutrition())
        XCTAssertEqual(try HealthKitStore.makeSamples(for: zeroSalt).map(\.quantityType), [Nutrient.calories.healthType])
    }

    func testSodiumFlowsThroughTodayHistoryAndNewPermissionRequest() async throws {
        let store = FakeNutritionStore(); store.writeStatuses[.sodium] = .notRequested
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        let previousRequests = store.accessRequests
        // Model an upgrade after the original permission request, before sodium was supported.
        store.writeStatuses[.sodium] = .notRequested
        try await manager.log(.init(name: "Soup", nutrition: .init(sodium: 500, estimated: [.sodium])))
        XCTAssertEqual(store.accessRequests, previousRequests + 1)
        XCTAssertEqual(manager.today.sodium, 500)
        XCTAssertEqual(manager.events.first?.nutrition.sodium, 500)
        XCTAssertEqual(manager.historyDays.first?.totals.sodium, 500)
        XCTAssertEqual(manager.today.estimated, [.sodium])
        XCTAssertNil(manager.today.caffeine)
    }

    func testExistingSodiumDenialIsNotRepeatedlyPromptedOrPartiallyLogged() async throws {
        let store = FakeNutritionStore()
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        let requests = store.accessRequests
        store.writeStatuses[.sodium] = .denied
        store.saveError = HealthAccessError.writeDenied(["Sodium"])
        do {
            try await manager.log(.init(name: "Soup", nutrition: .init(calories: 100, sodium: 500)))
            XCTFail("Expected denied sodium to reject the complete event")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Sodium"))
        }
        XCTAssertEqual(store.accessRequests, requests)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(manager.events.isEmpty)
        XCTAssertNil(manager.today.sodium)
    }
}
