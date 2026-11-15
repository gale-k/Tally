import Foundation

/// Editors work on a value snapshot, so cancelling cannot mutate a saved template.
struct DrinkDraft {
    var name = ""
    var brand = ""
    var size = ""
    var amount = ""
    var amountUnit: ServingAmountUnit = .millilitres
    var category: DrinkCategory = .other
    var servingStyle: ServingStyle = .other
    var isFavourite = false
    var notes = ""
    var values: [Nutrient: String] = [:]
    var estimated: Set<Nutrient> = []

    init() {}
    init(drink: SavedDrink) {
        name = drink.name; brand = drink.brandOrLocation ?? ""; size = drink.size ?? ""
        // Legacy templates have no weight and continue to open with their original ml amount.
        amountUnit = drink.weightG == nil ? .millilitres : .grams
        amount = (drink.weightG ?? drink.volumeMl).map { String($0) } ?? ""
        category = drink.category; servingStyle = drink.servingStyle
        isFavourite = drink.isFavourite; notes = drink.notes ?? ""
        for nutrient in drink.nutrition.knownNutrients { values[nutrient] = drink.nutrition[nutrient].map { String($0) } }
        estimated = drink.nutrition.estimated
    }

    static func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Reject malformed text instead of silently turning an invalid entry into an unknown value.
    static func parse(_ text: String, nutrient: Nutrient, locale: Locale = .current) throws -> Double? {
        guard let trimmed = optionalText(text) else { return nil }
        let separator = locale.decimalSeparator ?? "."
        let normalized = trimmed.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^([0-9]+(\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let number = Double(normalized), number.isFinite, number >= 0, number <= nutrient.inputLimit else {
            throw DrinkValidationError.invalidNumber(nutrient.title, nutrient.inputLimit, nutrient.unit)
        }
        return number
    }

    func nutrition() throws -> NutritionValues {
        var result = NutritionValues()
        for nutrient in Nutrient.allCases { result[nutrient] = try Self.parse(values[nutrient] ?? "", nutrient: nutrient) }
        result.estimated = estimated.intersection(Set(result.knownNutrients))
        try result.validate()
        return result
    }

    // Both units share the same optional positive-amount bounds; neither changes nutrition totals.
    func validatedAmount() throws -> Double? {
        guard let raw = Self.optionalText(amount) else { return nil }
        let normalized = raw.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0, value <= 100_000 else {
            throw DrinkValidationError.invalidAmount(amountUnit)
        }
        return value
    }

    func validate(requireName: Bool = true) throws {
        if requireName && Self.optionalText(name) == nil { throw DrinkValidationError.nameRequired }
        _ = try nutrition()
        _ = try validatedAmount()
    }

    func makeDrink() throws -> SavedDrink {
        try validate()
        let amount = try validatedAmount()
        return SavedDrink(name: name.trimmingCharacters(in: .whitespacesAndNewlines), brandOrLocation: Self.optionalText(brand),
                          size: Self.optionalText(size), volumeMl: amountUnit == .millilitres ? amount : nil,
                          weightG: amountUnit == .grams ? amount : nil, category: category,
                          servingStyle: servingStyle, nutrition: try nutrition(), notes: Self.optionalText(notes), isFavourite: isFavourite)
    }

    func apply(to drink: SavedDrink) throws {
        try validate()
        drink.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        drink.brandOrLocation = Self.optionalText(brand); drink.size = Self.optionalText(size)
        // Clear the previous unit's field so switching units cannot leave two competing measurements.
        let amount = try validatedAmount()
        drink.volumeMl = amountUnit == .millilitres ? amount : nil
        drink.weightG = amountUnit == .grams ? amount : nil
        drink.categoryRaw = category.rawValue
        drink.servingStyleRaw = servingStyle.rawValue; drink.isFavourite = isFavourite
        drink.notes = Self.optionalText(notes); drink.nutrition = try nutrition(); drink.updatedAt = .now
    }
}
