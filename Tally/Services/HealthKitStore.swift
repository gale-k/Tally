import Foundation
import HealthKit

/// All identifiers, units, metadata keys, and limited-access APIs were typechecked against the installed iOS 27 SDK.
extension Nutrient {
    var healthIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .caffeine: .dietaryCaffeine
        case .calories: .dietaryEnergyConsumed
        case .sugar: .dietarySugar
        case .carbohydrates: .dietaryCarbohydrates
        case .protein: .dietaryProtein
        case .totalFat: .dietaryFatTotal
        case .saturatedFat: .dietaryFatSaturated
        case .fibre: .dietaryFiber
        // Salt inputs have already been converted; Health receives one dietary sodium sample.
        case .sodium: .dietarySodium
        }
    }
    var healthUnit: HKUnit {
        switch self {
        case .caffeine, .sodium: .gramUnit(with: .milli)
        case .calories: .kilocalorie()
        default: .gram()
        }
    }
    var healthType: HKQuantityType { HKQuantityType(healthIdentifier) }
}

/// HealthKit persists the immutable nutrition samples; no parallel consumption database exists.
@MainActor
final class HealthKitStore: NutritionStore {
    private let store = HKHealthStore()
    let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "gale-k.Tally"
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Reverse-DNS custom metadata is app-owned. Standard HK keys retain their documented value types.
    nonisolated static let eventKey = "uk.gale.tally.eventID"
    nonisolated static let brandKey = "uk.gale.tally.brand"
    nonisolated static let sizeKey = "uk.gale.tally.size"
    nonisolated static let estimatedKey = "uk.gale.tally.estimated"
    nonisolated static let quantityKey = "uk.gale.tally.servingQuantity"
    nonisolated static let servingValueKey = "uk.gale.tally.servingValue"
    nonisolated static let servingUnitKey = "uk.gale.tally.servingUnit"
    nonisolated static let perServingKey = "uk.gale.tally.perServingValue"
    nonisolated static let nutrientsKey = "uk.gale.tally.nutrients"

    func requestAccess() async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
        let types = Set(Nutrient.allCases.map(\.healthType))
        try await store.requestAuthorization(toShare: types, read: types)
    }
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus {
        guard isAvailable else { return .notRequested }
        switch store.authorizationStatus(for: nutrient.healthType) {
        case .sharingAuthorized: return .allowed
        case .sharingDenied: return .denied
        default: return .notRequested
        }
    }

    static func makeSamples(for event: ConsumptionDraft, syncVersion: Int64 = 1) throws -> [HKQuantitySample] {
        try event.validate()
        let total = event.nutrition
        let nutrients = total.loggableNutrients
        let expectedNutrients = nutrients.map(\.rawValue).joined(separator: ",")
        return nutrients.map { nutrient in
            var metadata: [String: Any] = [
                HKMetadataKeyFoodType: event.name,
                HKMetadataKeyWasUserEntered: true,
                HKMetadataKeySyncIdentifier: syncIdentifier(eventID: event.id.uuidString, nutrient: nutrient),
                // HealthKit's sync version metadata uses NSNumber and retains 64-bit revisions.
                HKMetadataKeySyncVersion: NSNumber(value: syncVersion),
                eventKey: event.id.uuidString,
                estimatedKey: total.estimated.contains(nutrient),
                quantityKey: event.quantity,
                perServingKey: event.perServingNutrition[nutrient]!,
                nutrientsKey: expectedNutrients
            ]
            if let brand = event.brand { metadata[brandKey] = brand }
            if let size = event.size { metadata[sizeKey] = size }
            if let servingAmount = event.servingAmount {
                metadata[servingValueKey] = servingAmount.value
                metadata[servingUnitKey] = servingAmount.unit.rawValue
            }
            // A fresh sample and one shared timestamp make template edits independent of history.
            return HKQuantitySample(type: nutrient.healthType,
                                    quantity: HKQuantity(unit: nutrient.healthUnit, doubleValue: total[nutrient]!),
                                    start: event.date, end: event.date, metadata: metadata)
        }
    }

    func save(_ event: ConsumptionDraft) async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
        try checkWriteAccess(for: event.nutrition.loggableNutrients)
        // HKHealthStore guarantees that if any object fails, none of this array is saved.
        try await store.save(Self.makeSamples(for: event))
    }

    func verifyCurrent(_ event: ConsumptionEvent) async throws {
        guard event.canLogAgain else { throw HealthAccessError.incompleteEntry }
        _ = try await currentSamples(for: event)
    }

    func replace(_ event: ConsumptionEvent, with replacement: ConsumptionDraft) async throws {
        guard event.canModify else { throw HealthAccessError.incompleteEntry }
        let originals = try await currentSamples(for: event)
        let nutrients = Nutrient.allCases.filter { nutrient in originals.contains { $0.quantityType == nutrient.healthType } }
        try checkWriteAccess(for: nutrients)

        let existingVersions = originals.compactMap { sample -> Int64? in
            guard let nutrient = nutrients.first(where: { $0.healthType == sample.quantityType }),
                  sample.metadata?[HKMetadataKeySyncIdentifier] as? String == Self.syncIdentifier(eventID: replacement.id.uuidString, nutrient: nutrient),
                  let version = sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber else { return nil }
            return version.int64Value
        }
        if let latest = existingVersions.max() {
            // Every nutrient must keep the same sync ID. HealthKit replaces the whole saved array atomically.
            guard existingVersions.count == originals.count, originals.count == nutrients.count,
                  Set(nutrients) == Set(replacement.nutrition.loggableNutrients), latest < Int64.max else {
                throw HealthAccessError.incompleteEntry
            }
            // Keep the version increasing even after a clock rollback, with time ordering between devices.
            let timestampVersion = Int64(Date.now.timeIntervalSince1970 * 1_000_000)
            try await store.save(Self.makeSamples(for: replacement, syncVersion: max(latest + 1, timestampVersion)))
            return
        }
        guard originals.allSatisfy({ $0.metadata?[HKMetadataKeySyncIdentifier] == nil }) else {
            throw HealthAccessError.incompleteEntry
        }

        // Pre-quantity samples have no sync IDs. Keep them until the new array is safely saved.
        let staged = try Self.makeSamples(for: replacement)
        try await Self.replaceLegacySamples(originals, with: staged, save: { try await store.save($0) },
                                           delete: { try await store.delete($0) })
    }

    static func replaceLegacySamples(_ originals: [HKQuantitySample], with staged: [HKQuantitySample],
                                     save: ([HKQuantitySample]) async throws -> Void,
                                     delete: ([HKQuantitySample]) async throws -> Void) async throws {
        try await save(staged)
        do {
            try await delete(originals)
        } catch {
            // HealthKit deletes arrays atomically. On failure only the staged array needs rolling back.
            do { try await delete(staged) } catch { throw HealthAccessError.reconciliationFailed }
            throw error
        }
    }

    func delete(_ event: ConsumptionEvent) async throws {
        guard event.canModify else { throw HealthAccessError.incompleteEntry }
        let originals = try await currentSamples(for: event)
        try checkWriteAccess(for: Nutrient.allCases.filter { nutrient in originals.contains { $0.quantityType == nutrient.healthType } })
        try await store.delete(originals)
    }

    private func checkWriteAccess(for nutrients: [Nutrient]) throws {
        let denied = nutrients.filter { writeStatus(for: $0) != .allowed }
        guard denied.isEmpty else { throw HealthAccessError.writeDenied(denied.map(\.title)) }
    }

    private static func syncIdentifier(eventID: String, nutrient: Nutrient) -> String {
        "\(eventID).\(nutrient.rawValue)"
    }

    private func currentSamples(for event: ConsumptionEvent) async throws -> [HKQuantitySample] {
        guard isAvailable else { throw HealthAccessError.unavailable }
        guard event.isFromTally, !event.sampleIDs.isEmpty else { throw HealthAccessError.incompleteEntry }
        let identity: NSPredicate
        let metadataID: String?
        if event.id.hasPrefix("event:") {
            let id = String(event.id.dropFirst("event:".count))
            metadataID = id
            identity = HKQuery.predicateForObjects(withMetadataKey: Self.eventKey, allowedValues: [id])
        } else if event.id.hasPrefix("legacy:") {
            // HealthKit can query a date range; compare the exact timestamp and absent ID afterwards.
            metadataID = nil
            identity = HKQuery.predicateForSamples(withStart: event.date.addingTimeInterval(-1),
                                                   end: event.date.addingTimeInterval(1), options: [.strictStartDate, .strictEndDate])
        } else {
            throw HealthAccessError.incompleteEntry
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [HKQuery.predicateForObjects(from: HKSource.default()), identity])
        var records: [HKQuantitySample] = []
        for nutrient in Nutrient.allCases {
            records += try await quantitySamples(for: nutrient, matching: predicate).filter { sample in
                sample.sourceRevision.source.bundleIdentifier == ownBundleIdentifier &&
                    (metadataID != nil || (sample.startDate == event.date && sample.metadata?[Self.eventKey] == nil))
            }
        }
        guard Set(records.map(\.uuid)) == event.sampleIDs else { throw HealthAccessError.entryChanged }
        if records.allSatisfy({ $0.metadata?[Self.nutrientsKey] == nil }) {
            // Older records have no nutrient manifest to expose a hidden sample type.
            let limits = try await limitedReadDates()
            guard !limits.contains(where: { nutrient, cutoff in
                event.date < cutoff && !records.contains(where: { $0.quantityType == nutrient.healthType })
            }) else { throw HealthAccessError.incompleteEntry }
        }
        return records
    }

    func limitedReadDates() async throws -> [Nutrient: Date] {
        guard isAvailable else { throw HealthAccessError.unavailable }
        let dates = try await store.earliestAuthorizedSampleDate(for: Set(Nutrient.allCases.map(\.healthType)))
        return Dictionary(uniqueKeysWithValues: Nutrient.allCases.compactMap { nutrient in
            dates[nutrient.healthType].map { (nutrient, $0) }
        })
    }

    func samples(in range: DateInterval, limitedBy limits: [Nutrient: Date]) async throws -> [HealthSample] {
        guard isAvailable else { throw HealthAccessError.unavailable }
        var records: [HealthSample] = []
        for nutrient in Nutrient.allCases {
            let start = max(range.start, limits[nutrient] ?? range.start)
            guard start < range.end else { continue }
            let predicate = HKQuery.predicateForSamples(withStart: start, end: range.end, options: [.strictStartDate, .strictEndDate])
            records += try await quantitySamples(for: nutrient, matching: predicate).map { Self.readSample($0, nutrient: nutrient) }
        }
        return records
    }

    private func quantitySamples(for nutrient: Nutrient, matching predicate: NSPredicate) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: nutrient.healthType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    static func readSample(_ sample: HKQuantitySample, nutrient: Nutrient) -> HealthSample {
        let metadata = sample.metadata ?? [:]
        let amount: ServingAmount?
        if let value = metadata[servingValueKey] as? Double, value.isFinite, value > 0,
           let rawUnit = metadata[servingUnitKey] as? String, let unit = ServingAmountUnit(rawValue: rawUnit) {
            amount = ServingAmount(value: value, unit: unit)
        } else {
            amount = nil
        }
        // A manifest with an unknown future nutrient must fail completeness checks in older clients.
        let expected = (metadata[nutrientsKey] as? String).map { raw in
            let fields = raw.split(separator: ",", omittingEmptySubsequences: false)
            let parsed = fields.compactMap { Nutrient(rawValue: String($0)) }
            return parsed.count == fields.count ? Set(parsed) : []
        }
        return HealthSample(id: sample.uuid, nutrient: nutrient,
                            value: sample.quantity.doubleValue(for: nutrient.healthUnit), date: sample.startDate,
                            sourceName: sample.sourceRevision.source.name,
                            sourceBundle: sample.sourceRevision.source.bundleIdentifier,
                            eventID: metadata[eventKey] as? String,
                            drinkName: metadata[HKMetadataKeyFoodType] as? String,
                            brand: metadata[brandKey] as? String,
                            size: metadata[sizeKey] as? String,
                            isEstimated: metadata[estimatedKey] as? Bool ?? false,
                            servingQuantity: metadata[quantityKey] as? Double, servingAmount: amount,
                            perServingValue: metadata[perServingKey] as? Double, expectedNutrients: expected)
    }
}
