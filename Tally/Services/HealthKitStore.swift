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
    static let eventKey = "uk.gale.tally.eventID"
    static let brandKey = "uk.gale.tally.brand"
    static let sizeKey = "uk.gale.tally.size"
    static let estimatedKey = "uk.gale.tally.estimated"

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

    static func makeSamples(for event: ConsumptionDraft) throws -> [HKQuantitySample] {
        try event.validate()
        return event.nutrition.loggableNutrients.map { nutrient in
            var metadata: [String: Any] = [
                HKMetadataKeyFoodType: event.name,
                HKMetadataKeyWasUserEntered: true,
                eventKey: event.id.uuidString,
                estimatedKey: event.nutrition.estimated.contains(nutrient)
            ]
            if let brand = event.brand { metadata[brandKey] = brand }
            if let size = event.size { metadata[sizeKey] = size }
            // A fresh sample and one shared timestamp make template edits independent of history.
            return HKQuantitySample(type: nutrient.healthType,
                                    quantity: HKQuantity(unit: nutrient.healthUnit, doubleValue: event.nutrition[nutrient]!),
                                    start: event.date, end: event.date, metadata: metadata)
        }
    }

    func save(_ event: ConsumptionDraft) async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
        // Check authorization for the same nutrient types that will produce samples.
        let denied = event.nutrition.loggableNutrients.filter { writeStatus(for: $0) != .allowed }
        guard denied.isEmpty else { throw HealthAccessError.writeDenied(denied.map(\.title)) }
        // HKHealthStore guarantees that if any object fails, none of this array is saved.
        try await store.save(Self.makeSamples(for: event))
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
            let fetched: [HealthSample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(sampleType: nutrient.healthType, predicate: predicate,
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error); return }
                    let values = (samples as? [HKQuantitySample] ?? []).map { sample in
                        let metadata = sample.metadata ?? [:]
                        return HealthSample(id: sample.uuid, nutrient: nutrient,
                                            value: sample.quantity.doubleValue(for: nutrient.healthUnit), date: sample.startDate,
                                            sourceName: sample.sourceRevision.source.name,
                                            sourceBundle: sample.sourceRevision.source.bundleIdentifier,
                                            eventID: metadata["uk.gale.tally.eventID"] as? String,
                                            drinkName: metadata[HKMetadataKeyFoodType] as? String,
                                            brand: metadata["uk.gale.tally.brand"] as? String,
                                            size: metadata["uk.gale.tally.size"] as? String,
                                            isEstimated: metadata["uk.gale.tally.estimated"] as? Bool ?? false)
                    }
                    continuation.resume(returning: values)
                }
                store.execute(query)
            }
            records.append(contentsOf: fetched)
        }
        return records
    }
}
