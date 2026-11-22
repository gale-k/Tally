import Foundation

/// Supported nutrients share validation, formatting, and optional-value semantics.
enum Nutrient: String, CaseIterable, Codable, Identifiable, Sendable {
    case caffeine, calories, sugar, carbohydrates, protein, totalFat, saturatedFat, fibre, sodium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .caffeine: "Caffeine"
        case .calories: "Calories"
        case .sugar: "Sugar"
        case .carbohydrates: "Carbohydrates"
        case .protein: "Protein"
        case .totalFat: "Total Fat"
        case .saturatedFat: "Saturated Fat"
        case .fibre: "Fibre"
        case .sodium: "Sodium"
        }
    }
    // Sodium is canonical in milligrams, matching the values exchanged with Apple Health.
    var unit: String { self == .caffeine || self == .sodium ? "mg" : self == .calories ? "kcal" : "g" }
    // Balanced food-and-drink forms keep protein accessible without removing caffeine.
    static let formOrder: [Nutrient] = [.calories, .protein, .sugar, .caffeine, .carbohydrates, .totalFat, .saturatedFat, .fibre, .sodium]
    static let displayOrder: [Nutrient] = [.calories, .protein, .caffeine, .sugar, .carbohydrates, .fibre, .totalFat, .saturatedFat, .sodium]
    var isCore: Bool { [.calories, .protein, .sugar, .caffeine].contains(self) }
    // These generous input limits catch typing mistakes and keep aggregation finite; they are not health advice.
    var inputLimit: Double { self == .caffeine ? 10_000 : self == .calories ? 50_000 : 10_000 }
}

/// A missing value is unknown. Saved templates and Health history can retain explicit zeroes.
struct NutritionValues: Codable, Equatable, Sendable {
    var caffeine: Double?
    var calories: Double?
    var sugar: Double?
    var carbohydrates: Double?
    var protein: Double?
    var totalFat: Double?
    var saturatedFat: Double?
    var fibre: Double?
    // Optional additions decode as unknown in existing JSON snapshots and CloudKit payloads.
    var sodium: Double?
    var estimated: Set<Nutrient> = []

    subscript(_ nutrient: Nutrient) -> Double? {
        get {
            switch nutrient {
            case .caffeine: caffeine
            case .calories: calories
            case .sugar: sugar
            case .carbohydrates: carbohydrates
            case .protein: protein
            case .totalFat: totalFat
            case .saturatedFat: saturatedFat
            case .fibre: fibre
            case .sodium: sodium
            }
        }
        set {
            switch nutrient {
            case .caffeine: caffeine = newValue
            case .calories: calories = newValue
            case .sugar: sugar = newValue
            case .carbohydrates: carbohydrates = newValue
            case .protein: protein = newValue
            case .totalFat: totalFat = newValue
            case .saturatedFat: saturatedFat = newValue
            case .fibre: fibre = newValue
            case .sodium: sodium = newValue
            }
        }
    }
    var knownNutrients: [Nutrient] { Nutrient.allCases.filter { self[$0] != nil } }
    var isEmpty: Bool { knownNutrients.isEmpty }

    // New Health samples and their write permissions only apply to positive amounts.
    var loggableNutrients: [Nutrient] { Nutrient.allCases.filter { (self[$0] ?? 0) > 0 } }

    // Summaries show only known values. Foods without caffeine never get a misleading caffeine placeholder.
    var displayNutrients: [Nutrient] { Nutrient.displayOrder.filter { self[$0] != nil } }
    var summaryNutrients: [Nutrient] { Array(displayNutrients.prefix(2)) }
    func summaryLabel(_ nutrient: Nutrient) -> String {
        guard let amount = formatted(nutrient) else { return "" }
        return nutrient == .calories ? amount : "\(amount) \(nutrient.title.lowercased())"
    }
    var summaryText: String { displayNutrients.prefix(3).map { summaryLabel($0) }.joined(separator: " · ") }

    func validate() throws {
        for nutrient in knownNutrients {
            guard let value = self[nutrient], value.isFinite, value >= 0, value <= nutrient.inputLimit else {
                throw DrinkValidationError.invalidNumber(nutrient.title, nutrient.inputLimit, nutrient.unit)
            }
        }
    }

    func formatted(_ nutrient: Nutrient) -> String? {
        guard let value = self[nutrient] else { return nil }
        return "\(estimated.contains(nutrient) ? "~" : "")\(value.formatted(.number.precision(.fractionLength(0...2)))) \(nutrient.unit)"
    }
}

enum DrinkValidationError: LocalizedError {
    case nameRequired, noNutrition, invalidNumber(String, Double, String), invalidAmount(ServingAmountUnit), invalidDate
    var errorDescription: String? {
        switch self {
        case .nameRequired: "Give your item a name."
        case .noNutrition: "Enter at least one nutrient amount greater than zero to log to Apple Health."
        case let .invalidNumber(name, limit, unit): "Enter a number from 0 to \(limit.formatted()) \(unit) for \(name.lowercased())."
        // The selected unit is retained in validation feedback for both food and drink amounts.
        case let .invalidAmount(unit): "Enter an amount greater than 0 and no more than 100,000 \(unit.rawValue), or leave it blank."
        case .invalidDate: "Choose a valid date and time that is not in the future."
        }
    }
}
