#if DEBUG
import Foundation
import SwiftData

/// Explicitly invoked development presets. This file can be removed without changing production functionality.
@MainActor
enum DevelopmentData {
    static let marker = "developmentPresetsSeeded.v1"
    static func seed(in context: ModelContext, defaults: UserDefaults? = .standard) throws {
        guard defaults?.bool(forKey: marker) != true else { return }
        // Synthetic examples demonstrate optional nutrients; these are not nutrition reference data.
        // Keep the v1 marker: users who already added examples must never receive another surprise batch.
        let drinks: [SavedDrink] = [
            SavedDrink(name: "Yoghurt Bowl", size: "1 bowl", category: .dairyAlternatives,
                       nutrition: .init(calories: 260, sugar: 12, protein: 18, estimated: [.calories, .sugar, .protein]), isFavourite: true),
            SavedDrink(name: "Lunch Bowl", size: "1 serving", category: .meal,
                       nutrition: .init(calories: 380, carbohydrates: 42, protein: 24, fibre: 6, estimated: [.calories, .carbohydrates, .protein, .fibre]), isFavourite: true),
            SavedDrink(name: "Apple", size: "1 medium", category: .fruitVegetables,
                       nutrition: .init(calories: 95, carbohydrates: 25, fibre: 4, estimated: [.calories, .carbohydrates, .fibre])),
            SavedDrink(name: "Iced Mocha", brandOrLocation: "Fuel", size: "Iced", volumeMl: 470, category: .coffee, servingStyle: .iced,
                       nutrition: .init(caffeine: 100, estimated: [.caffeine]), isFavourite: true),
            SavedDrink(name: "Grande Caffè Latte", brandOrLocation: "Starbucks", size: "330 ml", volumeMl: 330, category: .coffee, servingStyle: .bottle,
                       nutrition: .init(caffeine: 125)),
            SavedDrink(name: "Chai Latte", brandOrLocation: "Fuel", size: "Medium", category: .teaChai, servingStyle: .hot,
                       nutrition: .init(caffeine: 0, estimated: [.caffeine]))
        ]
        do {
            for drink in drinks { context.insert(drink); try LibrarySyncStore.stage(drink, in: context) }
            try context.save()
            // Mark only a successful batch, so a failed save can be retried without partial seeds.
            defaults?.set(true, forKey: marker)
        } catch { context.rollback(); throw error }
    }
}
#endif
