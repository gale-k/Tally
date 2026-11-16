import Foundation

/// Adult starting points are comparisons, not personalised advice or permission to consume more.
/// This configuration is device-local and never becomes part of a template or Health sample.
struct DailyIntakeReference: Identifiable {
    enum Meaning { case reference, goal, personalTarget }
    let nutrient: Nutrient
    let defaultValue: Double
    let meaning: Meaning
    var id: Nutrient { nutrient }
    var title: String { nutrient == .sugar ? "Total Sugars" : nutrient.title }
    // Keep the original caffeine key so existing personal targets require no destructive migration.
    var valueKey: String { nutrient == .caffeine ? "dailyCaffeineTarget" : "dailyIntake.\(nutrient.rawValue).value" }
    var enabledKey: String { "dailyIntake.\(nutrient.rawValue).enabled" }

    static let all: [Self] = [
        .init(nutrient: .calories, defaultValue: 2_000, meaning: .reference),
        .init(nutrient: .protein, defaultValue: 50, meaning: .reference),
        .init(nutrient: .sugar, defaultValue: 90, meaning: .reference),
        .init(nutrient: .caffeine, defaultValue: 400, meaning: .personalTarget),
        .init(nutrient: .carbohydrates, defaultValue: 260, meaning: .reference),
        .init(nutrient: .totalFat, defaultValue: 70, meaning: .reference),
        .init(nutrient: .saturatedFat, defaultValue: 20, meaning: .reference),
        .init(nutrient: .fibre, defaultValue: 30, meaning: .goal)
    ]

    func label(for value: Double) -> String {
        if value != defaultValue || meaning == .personalTarget { return "Personal target" }
        return meaning == .goal ? "Adult daily goal" : "Adult reference intake"
    }
    func isValid(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= nutrient.inputLimit }

    /// The same strict, locale-aware parser as nutrition entry rejects partial and non-finite text.
    func parse(_ text: String, locale: Locale = .current) throws -> Double {
        guard let value = try DrinkDraft.parse(text, nutrient: nutrient, locale: locale), isValid(value) else {
            throw DailyIntakeInputError(nutrient: nutrient)
        }
        return value
    }
}

/// An explicit off switch keeps invalid numeric input distinct from disabling a comparison.
struct DailyIntakeInputError: LocalizedError {
    let nutrient: Nutrient
    var errorDescription: String? {
        "Enter a number greater than 0 and no more than \(nutrient.inputLimit.formatted()) \(nutrient.unit), or turn the comparison off."
    }
}

/// Only visible known totals produce progress. The visual bar caps at 100%; the text never does.
struct DailyIntakeProgress {
    let consumed: Double
    let target: Double
    let percentage: Double
    var fraction: Double { min(percentage / 100, 1) }
    var difference: Double { abs(target - consumed) }

    init?(consumed: Double?, target: Double) {
        guard let consumed, consumed.isFinite, consumed >= 0, target.isFinite, target > 0 else { return nil }
        let percentage = consumed / target * 100
        guard percentage.isFinite else { return nil }
        self.consumed = consumed; self.target = target; self.percentage = percentage
    }

    func status(for reference: DailyIntakeReference) -> String {
        let amount = "\(difference.formatted(.number.precision(.fractionLength(0...2)))) \(reference.nutrient.unit)"
        let isReference = reference.meaning == .reference && target == reference.defaultValue
        if consumed == target { return isReference ? "At reference intake" : "Target met" }
        if consumed < target { return "\(amount) to \(isReference ? "reference" : "target")" }
        // Protein and fibre are never treated as safety ceilings, including a user's custom goal.
        if reference.nutrient == .protein || reference.nutrient == .fibre {
            return "\(isReference ? "Reference reached" : "Target met") · \(amount) above"
        }
        return "\(amount) \(isReference ? "above reference" : "over personal target")"
    }
}
