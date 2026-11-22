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
        // Without a positive amount, HealthKit has no sample to represent this event.
        guard !nutrition.loggableNutrients.isEmpty else { throw DrinkValidationError.noNutrition }
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
    var recordedName: String?

    // Entries keeps its historical fallback. The drill-down identifies unnamed samples explicitly.
    var contributionName: String {
        let trimmed = recordedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? (isFromTally ? "Nutrition entry" : "Unnamed nutrition entry")
    }
}

struct HistoryDay: Identifiable, Sendable {
    var date: Date
    var events: [ConsumptionEvent]
    var totals: NutritionValues
    var id: Date { date }

    // An explicitly recorded zero still has a source and belongs in the drill-down.
    func contributions(for nutrient: Nutrient) -> [ConsumptionEvent] {
        events.filter { $0.nutrition[nutrient] != nil }
    }
}

/// Calendar arithmetic respects local midnight and daylight-saving changes.
enum DateWindows {
    static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }
    static func recent(days: Int, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: dayStart(daysAgo: max(1, days) - 1, now: now, calendar: calendar), end: now)
    }
    // Normalize each date separately because some time zones move their clocks at midnight.
    static func dayStart(daysAgo: Int, now: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!)
    }
    // DateInterval.contains includes the end point; day totals must use a half-open interval instead.
    static func contains(_ date: Date, in range: DateInterval) -> Bool { date >= range.start && date < range.end }

    // A refresh captures its calendar and time zone together; format with both during the same render.
    static func format(_ date: Date, as style: Date.FormatStyle, calendar: Calendar) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
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
                                    name: first.drinkName ?? (own ? "Nutrition entry" : first.nutrient.title),
                                    brand: own ? first.brand : nil, size: own ? first.size : nil,
                                    sourceName: first.sourceName, isFromTally: own, nutrition: try totals(records),
                                    recordedName: first.drinkName)
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
