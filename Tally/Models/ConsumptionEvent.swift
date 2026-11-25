import Foundation

/// A value snapshot deliberately has no relationship back to its editable template.
struct ConsumptionDraft: Sendable {
    let id: UUID
    let name: String
    let brand: String?
    let size: String?
    let perServingNutrition: NutritionValues
    let date: Date
    let quantity: Double
    let servingAmount: ServingAmount?

    var nutrition: NutritionValues { perServingNutrition.scaled(by: quantity) }

    init(id: UUID = UUID(), name: String, brand: String? = nil, size: String? = nil,
         nutrition: NutritionValues, date: Date = .now, quantity: Double = 1, servingAmount: ServingAmount? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.size = size
        perServingNutrition = nutrition; self.date = date
        self.quantity = quantity; self.servingAmount = servingAmount ?? ServingAmount(size: size)
    }
    func validate(now: Date = .now) throws {
        guard ServingQuantity.isValid(quantity) else { throw DrinkValidationError.invalidQuantity }
        try perServingNutrition.validate()
        // Without a positive amount, HealthKit has no sample to represent this event.
        let positiveNutrients = perServingNutrition.loggableNutrients
        guard !positiveNutrients.isEmpty else { throw DrinkValidationError.noNutrition }
        // Bounds in the editor apply to one serving. Totals may exceed them but must stay representable.
        let totals = nutrition
        guard positiveNutrients.allSatisfy({ ServingQuantity.isValid(totals[$0]!) }),
              servingAmount.map({ ServingQuantity.isValid($0.value * quantity) }) ?? true else {
            throw DrinkValidationError.quantityOutOfRange
        }
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
    var servingQuantity: Double? = nil
    var servingAmount: ServingAmount? = nil
    var perServingValue: Double? = nil
    var expectedNutrients: Set<Nutrient>? = nil
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
    var quantity: Double = 1
    var servingAmount: ServingAmount? = nil
    var perServingNutrition = NutritionValues()
    var sampleIDs: Set<UUID> = []
    var hasCompleteNutrition = false

    var canModify: Bool { isFromTally && hasCompleteNutrition }
    var canLogAgain: Bool { canModify && !perServingNutrition.loggableNutrients.isEmpty }

    func relogged(at date: Date = .now) throws -> ConsumptionDraft {
        guard canLogAgain else { throw HealthAccessError.incompleteEntry }
        return draft(id: UUID(), date: date, quantity: quantity)
    }

    func withQuantity(_ quantity: Double) throws -> ConsumptionDraft {
        guard canModify else { throw HealthAccessError.incompleteEntry }
        // Preserve event identity when available. Older timestamp groups acquire an ID on their first edit.
        let eventID = id.hasPrefix("event:") ? UUID(uuidString: String(id.dropFirst("event:".count))) : nil
        return draft(id: eventID ?? UUID(), date: date, quantity: quantity)
    }

    private func draft(id: UUID, date: Date, quantity: Double) -> ConsumptionDraft {
        ConsumptionDraft(id: id, name: name, brand: brand, size: size, nutrition: perServingNutrition,
                         date: date, quantity: quantity, servingAmount: servingAmount)
    }

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
            var event = ConsumptionEvent(id: key, date: first.date,
                                         name: first.drinkName ?? (own ? "Nutrition entry" : first.nutrient.title),
                                         brand: own ? first.brand : nil, size: own ? first.size : nil,
                                         sourceName: first.sourceName, isFromTally: own, nutrition: try totals(records),
                                         recordedName: first.drinkName)
            if own { addServingDetails(to: &event, records: ordered, first: first) }
            return event
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    private static func addServingDetails(to event: inout ConsumptionEvent, records: [HealthSample], first: HealthSample) {
        let nutrients = Set(records.map(\.nutrient))
        let consistent = nutrients.count == records.count && records.allSatisfy {
            $0.date == first.date && $0.drinkName == first.drinkName && $0.brand == first.brand && $0.size == first.size
                && $0.servingQuantity == first.servingQuantity && $0.servingAmount == first.servingAmount
                && $0.expectedNutrients == first.expectedNutrients
        }
        event.sampleIDs = Set(records.map(\.id))
        event.servingAmount = first.servingAmount ?? ServingAmount(size: first.size)
        // Legacy samples carry totals for a single serving. New samples store the original per-serving values.
        guard let quantity = first.servingQuantity else {
            event.perServingNutrition = event.nutrition
            event.hasCompleteNutrition = consistent && records.allSatisfy { $0.perServingValue == nil && $0.expectedNutrients == nil }
            return
        }
        guard ServingQuantity.isValid(quantity) else { return }
        event.quantity = quantity
        event.perServingNutrition.estimated = event.nutrition.estimated
        for record in records { event.perServingNutrition[record.nutrient] = record.perServingValue }
        event.hasCompleteNutrition = consistent && first.expectedNutrients == nutrients && records.allSatisfy {
            $0.perServingValue.map(ServingQuantity.isValid) ?? false
        }
    }
}
