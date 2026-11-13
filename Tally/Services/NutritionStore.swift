import Foundation

/// The system adapter is replaceable in tests; neither core grouping nor coordinator tests need HealthKit access.
@MainActor
protocol NutritionStore {
    var isAvailable: Bool { get }
    var ownBundleIdentifier: String { get }
    func requestAccess() async throws
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus
    func save(_ event: ConsumptionDraft) async throws
    func samples(in range: DateInterval) async throws -> [HealthSample]
    func limitedReadDates() async throws -> [Nutrient: Date]
}

enum NutritionWriteStatus: String, Sendable {
    case notRequested = "Not requested", allowed = "Allowed", denied = "Not allowed"
}

enum HealthAccessError: LocalizedError {
    case unavailable, writeDenied([String]), invalidData, alreadySaving
    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device. Your saved library is still available."
        case let .writeDenied(names): "Allow Tally to write \(names.joined(separator: ", ")) in Health → your profile → Apps → Tally. No nutrition was saved."
        case .invalidData: "Some Apple Health nutrition could not be read safely. Please check the source entries in Health and try again."
        case .alreadySaving: "An entry is already being saved. Please wait a moment."
        }
    }
}
