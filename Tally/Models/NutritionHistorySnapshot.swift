import Foundation

/// A refresh groups each local day's visible samples once for Entries, Today, Trends and drill-downs.
struct NutritionHistorySnapshot {
    static let dayCount = 30
    let calendar: Calendar
    let days: [HistoryDay]
    let limitedDates: [Nutrient: Date]
    private let now: Date

    init(samples: [HealthSample], ownBundle: String, limitedDates: [Nutrient: Date], now: Date, calendar: Calendar) throws {
        self.calendar = calendar
        self.limitedDates = limitedDates
        self.now = now
        let window = DateWindows.recent(days: Self.dayCount, now: now, calendar: calendar)
        // Apply the same bounds when using cached records after a clock or read-window change.
        let visible = samples.filter { sample in
            DateWindows.contains(sample.date, in: window)
                && sample.date >= (limitedDates[sample.nutrient] ?? window.start)
        }
        let grouped = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.date) }
        days = try (0..<Self.dayCount).reversed().map { offset in
            let date = DateWindows.dayStart(daysAgo: offset, now: now, calendar: calendar)
            let records = grouped[date] ?? []
            return HistoryDay(date: date, events: try HealthAggregation.events(records, ownBundle: ownBundle),
                              totals: try HealthAggregation.totals(records))
        }
    }

    var today: HistoryDay { days[days.count - 1] }

    // Store selection by local date so it still points to the same calendar day after a time-zone change.
    func dayKey(for date: Date) -> DateComponents {
        calendar.dateComponents([.era, .year, .month, .day], from: date)
    }

    enum ReadWindow {
        case full, partial, outside
    }

    func readWindow(on day: HistoryDay, for nutrient: Nutrient) -> ReadWindow {
        guard let limit = limitedDates[nutrient], limit > day.date else { return .full }
        let end = min(now, DateWindows.day(containing: day.date, calendar: calendar).end)
        return limit >= end ? .outside : .partial
    }
}

/// Completed days without a visible sample stay out of the mean. A zero counts as a measured day.
struct NutrientTrendSummary {
    let completedCount: Int
    let visibleCount: Int
    let average: NutritionValues

    init(days: ArraySlice<HistoryDay>, nutrient: Nutrient) {
        let completed = days.dropLast()
        var count = 0
        var mean = 0.0
        var result = NutritionValues()
        for day in completed {
            guard let value = day.totals[nutrient] else { continue }
            count += 1
            // An incremental mean stays finite even if the sum across days would overflow.
            mean += (value - mean) / Double(count)
            if day.totals.estimated.contains(nutrient) { result.estimated.insert(nutrient) }
        }
        if count > 0 { result[nutrient] = mean }
        completedCount = completed.count
        visibleCount = count
        average = result
    }
}
