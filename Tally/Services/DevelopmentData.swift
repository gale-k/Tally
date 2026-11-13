#if DEBUG
import Foundation
import SwiftData

/// Explicitly invoked development presets. This file can be removed without changing production functionality.
@MainActor
enum DevelopmentData {
    static let marker = "developmentPresetsSeeded.v1"
    static func seed(in context: ModelContext, defaults: UserDefaults? = .standard) throws {
        guard defaults?.bool(forKey: marker) != true else { return }
        let drinks: [SavedDrink] = [
            SavedDrink(name: "Iced Mocha", brandOrLocation: "Fuel", size: "Iced", volumeMl: 470, category: .coffee, servingStyle: .iced, nutrition: .init(caffeine: 100, estimated: [.caffeine]), isFavourite: true),
            SavedDrink(name: "Large Latte", brandOrLocation: "Fuel", size: "Large", nutrition: .init(caffeine: 100, estimated: [.caffeine])),
            SavedDrink(name: "Large Mocha", brandOrLocation: "Fuel", size: "Large", nutrition: .init(caffeine: 100, estimated: [.caffeine])),
            SavedDrink(name: "Chai Latte", brandOrLocation: "Fuel", size: "Medium", category: .teaChai, nutrition: .init(caffeine: 0, estimated: [.caffeine])),
            SavedDrink(name: "Chai Latte", brandOrLocation: "Caffè Nero", size: "Large", category: .teaChai, nutrition: .init(caffeine: 10, estimated: [.caffeine])),
            SavedDrink(name: "Grande Caffè Latte", brandOrLocation: "Starbucks", size: "330 ml", volumeMl: 330, category: .coffee, servingStyle: .bottle, nutrition: .init(caffeine: 125)),
            SavedDrink(name: "Nespresso Pod", brandOrLocation: "Nespresso / Wonky", size: "1 pod", category: .pod, servingStyle: .pod, nutrition: .init(caffeine: 100, estimated: [.caffeine]))
        ]
        do {
            for drink in drinks { context.insert(drink) }
            try context.save()
            // Mark only a successful batch, so a failed save can be retried without partial seeds.
            defaults?.set(true, forKey: marker)
        } catch { context.rollback(); throw error }
    }
}
#endif
