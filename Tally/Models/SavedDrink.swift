import Foundation
import SwiftData

/// Raw values keep the persistent schema stable when display names change.
enum DrinkCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case meal, snack, fruitVegetables, dairyAlternatives, coffee, energyDrink, teaChai, pod, softDrink, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meal: "Meal"
        case .snack: "Snack"
        case .fruitVegetables: "Fruit & Vegetables"
        case .dairyAlternatives: "Dairy & Alternatives"
        case .coffee: "Coffee"
        case .energyDrink: "Energy Drink"
        case .teaChai: "Tea / Chai"
        case .pod: "Nespresso / Pod"
        case .softDrink: "Soft Drink"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .meal: "fork.knife"
        // The shared category icon uses a wrapped sweet asset; this remains a system-symbol fallback.
        case .snack: "birthday.cake.fill"
        case .fruitVegetables: "leaf.fill"
        case .dairyAlternatives: "refrigerator.fill"
        case .coffee: "cup.and.saucer.fill"
        case .energyDrink: "bolt.fill"
        case .teaChai: "mug.fill"
        case .pod: "circle.hexagongrid.fill"
        case .softDrink: "waterbottle.fill"
        case .other: "list.bullet.clipboard.fill"
        }
    }
}

enum ServingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    // Cold is separate from iced so chilled items do not imply added ice.
    case hot, cold, iced, can, bottle, pod, other
    var id: String { rawValue }
    // The existing raw value represents an unspecified style without changing the stored schema.
    var title: String { self == .other ? "Not specified" : rawValue.capitalized }
}

/// Units describe a serving amount; changing units does not perform a mass/volume conversion.
enum ServingAmountUnit: String, CaseIterable, Identifiable, Sendable {
    case millilitres = "ml", grams = "g"
    var id: String { rawValue }
    var title: String { self == .grams ? "grams" : "millilitres" }
}

/// The legacy model name preserves existing stores and JSON. Templates now cover foods and drinks.
/// Actual consumption is never stored in SwiftData.
@Model
final class SavedDrink {
    @Attribute(.unique) var id: UUID
    var name: String
    var brandOrLocation: String?
    var size: String?
    var volumeMl: Double?
    // An additive optional property preserves existing liquid amounts and allows lightweight store migration.
    var weightG: Double?
    var categoryRaw: String
    var servingStyleRaw: String
    var caffeineMg: Double?
    var caloriesKcal: Double?
    var sugarG: Double?
    var carbohydratesG: Double?
    var proteinG: Double?
    var totalFatG: Double?
    var saturatedFatG: Double?
    var fibreG: Double?
    // Additive optional storage preserves existing templates through lightweight migration.
    var sodiumMg: Double?
    var estimatedNutrients: [String]
    var notes: String?
    var isFavourite: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastLoggedAt: Date?
    var timesLogged: Int

    init(id: UUID = UUID(), name: String, brandOrLocation: String? = nil, size: String? = nil,
         volumeMl: Double? = nil, weightG: Double? = nil, category: DrinkCategory = .other, servingStyle: ServingStyle = .other,
         nutrition: NutritionValues = .init(), notes: String? = nil, isFavourite: Bool = false,
         createdAt: Date = .now, updatedAt: Date = .now, lastLoggedAt: Date? = nil, timesLogged: Int = 0) {
        self.id = id
        self.name = name
        self.brandOrLocation = brandOrLocation
        self.size = size
        self.volumeMl = volumeMl
        self.weightG = weightG
        self.categoryRaw = category.rawValue
        self.servingStyleRaw = servingStyle.rawValue
        caffeineMg = nutrition.caffeine
        caloriesKcal = nutrition.calories
        sugarG = nutrition.sugar
        carbohydratesG = nutrition.carbohydrates
        proteinG = nutrition.protein
        totalFatG = nutrition.totalFat
        saturatedFatG = nutrition.saturatedFat
        fibreG = nutrition.fibre
        sodiumMg = nutrition.sodium
        estimatedNutrients = nutrition.estimated.map(\.rawValue).sorted()
        self.notes = notes
        self.isFavourite = isFavourite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastLoggedAt = lastLoggedAt
        self.timesLogged = timesLogged
    }

    var category: DrinkCategory { DrinkCategory(rawValue: categoryRaw) ?? .other }
    var servingStyle: ServingStyle { ServingStyle(rawValue: servingStyleRaw) ?? .other }
    var nutrition: NutritionValues {
        get { .init(caffeine: caffeineMg, calories: caloriesKcal, sugar: sugarG, carbohydrates: carbohydratesG,
                    protein: proteinG, totalFat: totalFatG, saturatedFat: saturatedFatG, fibre: fibreG, sodium: sodiumMg,
                    estimated: Set(estimatedNutrients.compactMap(Nutrient.init(rawValue:)))) }
        set {
            caffeineMg = newValue.caffeine; caloriesKcal = newValue.calories; sugarG = newValue.sugar
            carbohydratesG = newValue.carbohydrates; proteinG = newValue.protein; totalFatG = newValue.totalFat
            saturatedFatG = newValue.saturatedFat; fibreG = newValue.fibre
            sodiumMg = newValue.sodium
            estimatedNutrients = newValue.estimated.map(\.rawValue).sorted()
        }
    }
}
