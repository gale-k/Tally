#if DEBUG
import Foundation
import SwiftUI

/// UI-test launch arguments are compiled out of Release. Synthetic samples never reach HKHealthStore.
@MainActor
final class FixtureNutritionStore: NutritionStore {
    let ownBundleIdentifier = "gale-k.Tally"
    var isAvailable: Bool { !ProcessInfo.processInfo.arguments.contains("--health-unavailable") }
    private var logged: [ConsumptionDraft] = []
    private let populated: Bool
    init(populated: Bool) { self.populated = populated }
    func requestAccess() async throws {
        guard isAvailable else { throw HealthAccessError.unavailable }
    }
    func writeStatus(for nutrient: Nutrient) -> NutritionWriteStatus {
        ProcessInfo.processInfo.arguments.contains("--write-denied") && nutrient == .caffeine ? .denied : .allowed
    }
    func save(_ event: ConsumptionDraft) async throws {
        // Mirror the production write checks so a skipped zero cannot cause a fixture-only denial.
        try event.validate()
        let denied = event.nutrition.loggableNutrients.filter { writeStatus(for: $0) != .allowed }
        guard denied.isEmpty else { throw HealthAccessError.writeDenied(denied.map(\.title)) }
        logged.append(event)
    }
    func limitedReadDates() async throws -> [Nutrient: Date] {
        // The Trends fixture models a cutoff partway through the third previous day.
        guard ProcessInfo.processInfo.arguments.contains("--trend-fixture") else { return [:] }
        let day = DateWindows.dayStart(daysAgo: 3, now: .now, calendar: .current)
        return [.sodium: day.addingTimeInterval(1_800)]
    }
    func samples(in range: DateInterval, limitedBy limits: [Nutrient: Date]) async throws -> [HealthSample] {
        if ProcessInfo.processInfo.arguments.contains("--query-failure") { throw HealthAccessError.invalidData }
        var events = logged
        if populated {
            let start = Calendar.current.startOfDay(for: .now)
            // Stable relative dates keep these explicitly synthetic fixtures useful on any test day.
            events += [
                .init(name: "Iced Mocha", brand: "Fuel", nutrition: .init(caffeine: 100, calories: 220, sugar: 24, estimated: [.caffeine]), date: start.addingTimeInterval(60)),
                .init(name: "Lunch Bowl", nutrition: .init(calories: 380, carbohydrates: 42, protein: 24, fibre: 6, estimated: [.calories]), date: start.addingTimeInterval(90)),
                .init(name: "Grande Caffè Latte", brand: "Starbucks", nutrition: .init(caffeine: 125), date: start.addingTimeInterval(120))
            ]
            // Opt-in sodium gives the layout test a visible bar without altering other fixtures.
            if ProcessInfo.processInfo.arguments.contains("--populated-sodium") {
                events.append(.init(name: "Soup", nutrition: .init(sodium: 800), date: start.addingTimeInterval(150)))
            }
            for offset in 1...6 {
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: start)!.addingTimeInterval(3_600)
                events.append(.init(name: "Coffee", nutrition: .init(caffeine: Double(100 + offset * 20)), date: date))
            }
        }
        var samples = events.flatMap { event in
            event.nutrition.loggableNutrients.map { nutrient in
                HealthSample(id: UUID(), nutrient: nutrient, value: event.nutrition[nutrient]!, date: event.date,
                             sourceName: "Tally", sourceBundle: ownBundleIdentifier, eventID: event.id.uuidString,
                             drinkName: event.name, brand: event.brand, size: event.size,
                             isEstimated: event.nutrition.estimated.contains(nutrient))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--trend-fixture") {
            // Seed existing Health samples directly so the recorded zero bypasses new-entry validation.
            let now = range.end
            func makeSample(_ amount: Double, daysAgo: Int, name: String?, estimated: Bool = false) -> HealthSample {
                let date = DateWindows.dayStart(daysAgo: daysAgo, now: now, calendar: .current).addingTimeInterval(3_600)
                return HealthSample(id: UUID(), nutrient: .sodium, value: amount, date: date,
                                    sourceName: name == nil ? "Other Nutrition" : "Tally",
                                    sourceBundle: name == nil ? "example.nutrition" : ownBundleIdentifier,
                                    drinkName: name, isEstimated: estimated)
            }
            samples += [makeSample(0, daysAgo: 1, name: "Plain water"),
                        makeSample(300, daysAgo: 3, name: "Soup", estimated: true),
                        makeSample(200, daysAgo: 3, name: nil)]
        }
        return samples.filter { DateWindows.contains($0.date, in: range) }
    }
}

/// Appearance overrides exist only for repeatable runtime screenshot tests; normal launches respect system settings.
struct DevelopmentAppearance: ViewModifier {
    // Apply one presentation preference so the outer appearance setting cannot mask a test override.
    var appAppearance: AppAppearance? = nil

    func body(content: Content) -> some View {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && !args.contains("--test-appearance-setting") {
            if args.contains("--large-text") {
                content.preferredColorScheme(args.contains("--dark-mode") ? .dark : .light)
                    .dynamicTypeSize(.accessibility3)
            } else { content.preferredColorScheme(args.contains("--dark-mode") ? .dark : .light) }
        } else if let appAppearance {
            content.preferredColorScheme(appAppearance.colorScheme)
        } else { content }
    }
}
#endif
