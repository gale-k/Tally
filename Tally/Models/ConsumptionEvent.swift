import Foundation

/// A value snapshot deliberately has no relationship back to its editable template.
struct ConsumptionDraft: Sendable {
    let id: UUID
    let name: String
    let brand: String?
    let size: String?
    let nutrition: NutritionValues
    let date: Date

    init(id: UUID = UUID(), name: String, brand: String? = nil, size: String? = nil,
         nutrition: NutritionValues, date: Date = .now) {
        self.id = id; self.name = name; self.brand = brand; self.size = size
        self.nutrition = nutrition; self.date = date
    }
    func validate(now: Date = .now) throws {
        try nutrition.validate()
        guard !nutrition.isEmpty else { throw DrinkValidationError.noNutrition }
        guard date.timeIntervalSince1970.isFinite, date <= now else { throw DrinkValidationError.invalidDate }
    }
}

/// Only transient, in-memory representations of HealthKit samples are used for history.
struct HealthSample: Identifiable, Sendable {
    var id: UUID
    var nutrient: Nutrient
    var value: Double
    var date: Date
    var sourceName: String
    var sourceBundle: String
    var eventID: String?
    var drinkName: String?
    var brand: String?
    var size: String?
    var isEstimated: Bool
}

struct ConsumptionEvent: Identifiable, Sendable {
    var id: String
    var date: Date
    var name: String
    var brand: String?
    var size: String?
    var sourceName: String
    var isFromTally: Bool
    var nutrition: NutritionValues
}

struct HistoryDay: Identifiable, Sendable {
    var date: Date
    var events: [ConsumptionEvent]
    var totals: NutritionValues
    var id: Date { date }
}

struct CaffeineDay: Identifiable, Sendable {
    var date: Date
    var total: Double?
    var isEstimated = false
    var id: Date { date }
}

/// Calendar arithmetic respects local midnight and daylight-saving changes.
enum DateWindows {
    static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
    static func recent(days: Int, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now))!
        return DateInterval(start: start, end: now)
    }
    // DateInterval.contains includes the end point; day totals must use a half-open interval instead.
    static func contains(_ date: Date, in range: DateInterval) -> Bool { date >= range.start && date < range.end }
}

enum HealthAggregation {
    static func totals(_ samples: [HealthSample]) throws -> NutritionValues {
        var result = NutritionValues()
        for sample in samples {
            let sum = (result[sample.nutrient] ?? 0) + sample.value
            guard sample.value.isFinite, sample.value >= 0, sum.isFinite else { throw HealthAccessError.invalidData }
            result[sample.nutrient] = sum
            if sample.isEstimated { result.estimated.insert(sample.nutrient) }
        }
        return result
    }

    static func events(_ samples: [HealthSample], ownBundle: String) throws -> [ConsumptionEvent] {
        let groups = Dictionary(grouping: samples) { sample in
            // Never combine another app's samples by time, nor trust copied Tally metadata from another source.
            guard sample.sourceBundle == ownBundle else { return "sample:\(sample.id.uuidString)" }
            if let id = sample.eventID { return "event:\(id)" }
            return "legacy:\(sample.date.timeIntervalSince1970)"
        }
        return try groups.map { key, records in
            let ordered = records.sorted { $0.id.uuidString < $1.id.uuidString }
            let first = ordered[0]
            let own = first.sourceBundle == ownBundle
            return ConsumptionEvent(id: key, date: first.date,
                                    name: first.drinkName ?? (own ? "Drink" : first.nutrient.title),
                                    brand: own ? first.brand : nil, size: own ? first.size : nil,
                                    sourceName: first.sourceName, isFromTally: own, nutrition: try totals(records))
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    static func historyDays(_ samples: [HealthSample], events: [ConsumptionEvent], calendar: Calendar = .current) throws -> [HistoryDay] {
        let sampleDays = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
        let eventDays = Dictionary(grouping: events) { calendar.startOfDay(for: $0.date) }
        return try eventDays.map { date, events in
            HistoryDay(date: date, events: events.sorted { $0.date > $1.date }, totals: try totals(sampleDays[date] ?? []))
        }.sorted { $0.date > $1.date }
    }

    static func caffeineDays(_ samples: [HealthSample], count: Int, now: Date = .now,
                             calendar: Calendar = .current) throws -> [CaffeineDay] {
        try (0..<count).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
            let range = DateWindows.day(containing: date, calendar: calendar)
            let nutrition = try totals(samples.filter { $0.nutrient == .caffeine && DateWindows.contains($0.date, in: range) })
            return CaffeineDay(date: date, total: nutrition.caffeine, isEstimated: nutrition.estimated.contains(.caffeine))
        }
    }
}
