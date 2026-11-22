import Foundation
import Observation

/// Coordinates visible state without claiming to know the user's private read-authorization choices.
@MainActor @Observable
final class HealthKitManager {
    private let client: any NutritionStore
    private let defaults: UserDefaults?
    private var refreshID = UUID()
    private var samples: [HealthSample] = []
    private(set) var permissionsRequested: Bool
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var nutritionHistory: NutritionHistorySnapshot?
    private(set) var queryError: String?
    private(set) var lastRefreshed: Date?

    // Existing dashboard and History consumers project from the same snapshot as Trends.
    var today: NutritionValues { nutritionHistory?.today.totals ?? NutritionValues() }
    var todayEvents: [ConsumptionEvent] { nutritionHistory?.today.events ?? [] }
    var historyDays: [HistoryDay] { nutritionHistory?.days.reversed().filter { !$0.events.isEmpty } ?? [] }
    var events: [ConsumptionEvent] { historyDays.flatMap(\.events) }
    var limitedDates: [Nutrient: Date] { nutritionHistory?.limitedDates ?? [:] }

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
        // An existing user may have reviewed permissions before a newly supported nutrient was added.
        // Only the nutrients being written can reopen the permission sheet on first use.
        if !permissionsRequested || event.nutrition.loggableNutrients.contains(where: { client.writeStatus(for: $0) == .notRequested }) {
            try await requestAccess()
        }
        try await client.save(event)
        await refresh()
    }

    func refresh(now: Date = .now, calendar: Calendar = .current) async {
        guard isAvailable, permissionsRequested else { return }
        let token = UUID()
        refreshID = token
        isLoading = true
        defer { if refreshID == token { isLoading = false } }
        var limits = limitedDates
        if let snapshot = nutritionHistory,
           snapshot.calendar != calendar || snapshot.today.date != calendar.startOfDay(for: now) || now < (lastRefreshed ?? now) {
            // Rebucket retained samples immediately so yesterday's total never appears under today's date.
            nutritionHistory = try? makeSnapshot(samples, limits: limits, now: now, calendar: calendar)
        }
        do {
            limits = try await client.limitedReadDates()
            let range = DateWindows.recent(days: NutritionHistorySnapshot.dayCount, now: now, calendar: calendar)
            let records = try await client.samples(in: range, limitedBy: limits)
            let snapshot = try makeSnapshot(records, limits: limits, now: now, calendar: calendar)
            // A stale foreground refresh must not overwrite a newer post-save response.
            guard refreshID == token else { return }
            samples = records
            nutritionHistory = snapshot
            queryError = nil
            lastRefreshed = now
        } catch {
            guard refreshID == token else { return }
            if let snapshot = nutritionHistory {
                // Apply tighter limits immediately. Only a successful fetch can widen the cached read window.
                let retainedLimits = snapshot.limitedDates.merging(limits, uniquingKeysWith: max)
                if retainedLimits != snapshot.limitedDates {
                    nutritionHistory = try? makeSnapshot(samples, limits: retainedLimits, now: now, calendar: calendar)
                }
            }
            queryError = "Couldn’t refresh Apple Health. \(error.localizedDescription)"
        }
    }

    private func makeSnapshot(_ records: [HealthSample], limits: [Nutrient: Date], now: Date,
                              calendar: Calendar) throws -> NutritionHistorySnapshot {
        try NutritionHistorySnapshot(samples: records, ownBundle: client.ownBundleIdentifier,
                                     limitedDates: limits, now: now, calendar: calendar)
    }
}
