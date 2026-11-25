import Foundation

/// The system adapter is replaceable in tests; neither core grouping nor coordinator tests need HealthKit access.
@MainActor
protocol NutritionStore {
    var isAvailable: Bool { get }
    var ownBundleIdentifier: String { get }
    func requestAccess() async throws
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus
    func save(_ event: ConsumptionDraft) async throws
    // History actions resolve the original samples again before working from a visible snapshot.
    func verifyCurrent(_ event: ConsumptionEvent) async throws
    func replace(_ event: ConsumptionEvent, with replacement: ConsumptionDraft) async throws
    func delete(_ event: ConsumptionEvent) async throws
    // The refresh uses these same per-type limits for querying and explaining visible coverage.
    func samples(in range: DateInterval, limitedBy limits: [Nutrient: Date]) async throws -> [HealthSample]
    func limitedReadDates() async throws -> [Nutrient: Date]
}

enum NutritionWriteStatus: String, Sendable {
    case notRequested = "Not requested", allowed = "Allowed", denied = "Not allowed"
}

enum HealthAccessError: LocalizedError {
    case unavailable, writeDenied([String]), invalidData, alreadySaving, entryChanged, incompleteEntry, reconciliationFailed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device. Your saved library is still available."
        case let .writeDenied(names): "Allow Tally to write \(names.joined(separator: ", ")) in Health → your profile → Apps → Tally. No nutrition was saved."
        case .invalidData: "Some Apple Health nutrition could not be read safely. Please check the source entries in Health and try again."
        case .alreadySaving: "An entry is already being saved. Please wait a moment."
        case .entryChanged: "This entry has changed in Apple Health. Refresh History and try again."
        case .incompleteEntry: "Tally couldn’t verify all the nutrition for this entry in Apple Health. Review the entry and Tally’s Health access before trying again."
        case .reconciliationFailed: "Apple Health couldn’t finish the quantity change or remove the replacement samples. Check the entry in Health before trying again."
        }
    }
}
