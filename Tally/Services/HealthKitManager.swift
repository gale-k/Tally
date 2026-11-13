import Foundation
import Observation

/// Coordinates visible state without claiming to know the user's private read-authorization choices.
@MainActor @Observable
final class HealthKitManager {
    private let client: any NutritionStore
    private let defaults: UserDefaults?
    private var refreshID = UUID()
    private(set) var permissionsRequested: Bool
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var samples: [HealthSample] = []
    private(set) var events: [ConsumptionEvent] = []
    private(set) var historyDays: [HistoryDay] = []
    private(set) var today = NutritionValues()
    private(set) var caffeineDays: [CaffeineDay] = []
    private(set) var limitedDates: [Nutrient: Date] = [:]
    private(set) var queryError: String?
    private(set) var lastRefreshed: Date?

    init(client: any NutritionStore = HealthKitStore(), defaults: UserDefaults? = .standard) {
        self.client = client; self.defaults = defaults
        permissionsRequested = defaults?.bool(forKey: "healthPermissionsRequested") ?? false
    }
    var isAvailable: Bool { client.isAvailable }
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus { client.writeStatus(for: nutrient) }

    func requestAccess() async throws {
        try await client.requestAccess()
        // Completing the permission sheet says nothing about read access being granted.
        permissionsRequested = true
        defaults?.set(true, forKey: "healthPermissionsRequested")
        await refresh()
    }

    func log(_ event: ConsumptionDraft) async throws {
        guard !isSaving else { throw HealthAccessError.alreadySaving }
        guard isAvailable else { throw HealthAccessError.unavailable }
        try event.validate()
        isSaving = true
        defer { isSaving = false }
        if !permissionsRequested { try await requestAccess() }
        try await client.save(event)
        await refresh()
    }

    func refresh(now: Date = .now) async {
        guard isAvailable, permissionsRequested else { return }
        let token = UUID()
        refreshID = token
        isLoading = true
        defer { if refreshID == token { isLoading = false } }
        do {
            let records = try await client.samples(in: DateWindows.recent(days: 30, now: now))
            let limits = try await client.limitedReadDates()
            let grouped = try HealthAggregation.events(records, ownBundle: client.ownBundleIdentifier)
            let history = try HealthAggregation.historyDays(records, events: grouped)
            let daily = try HealthAggregation.totals(records.filter { DateWindows.contains($0.date, in: DateWindows.day(containing: now)) })
            let trend = try HealthAggregation.caffeineDays(records, count: 7, now: now)
            // A stale foreground refresh must not overwrite a newer post-save response.
            guard refreshID == token else { return }
            samples = records; events = grouped; historyDays = history; today = daily; caffeineDays = trend
            limitedDates = limits; queryError = nil; lastRefreshed = now
        } catch {
            guard refreshID == token else { return }
            queryError = "Couldn’t refresh Apple Health. \(error.localizedDescription)"
        }
    }
}
