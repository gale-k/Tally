import XCTest
@testable import Tally

final class NutritionTrendTests: XCTestCase {
    // The same day reconciles app-owned and third-party entries, estimates, and a recorded zero.
    func testDatedContributionsAndAverageUseVisibleValuesOnly() throws {
        let calendar = calendar(in: "Europe/London")
        let now = instant("2026-03-30T11:00:00Z")
        let mixed = instant("2026-03-28T11:00:00Z")
        let firstReadable = instant("2026-03-28T10:00:00Z")
        let history = try NutritionHistorySnapshot(samples: [
            sample(.sodium, 600, instant("2026-03-27T12:00:00Z")),
            sample(.sodium, 900, instant("2026-03-28T09:59:59Z")),
            sample(.sodium, 300, mixed, estimated: true),
            sample(.sodium, 200, mixed, source: "Other App", name: " "),
            sample(.sodium, 0, instant("2026-03-29T10:00:00Z")),
            sample(.sodium, 800, instant("2026-03-30T09:00:00Z")),
            sample(.sodium, 400, now)
        ], ownBundle: "own", limitedDates: [.sodium: firstReadable], now: now, calendar: calendar)

        for (count, completed) in [(7, 6), (30, 29)] {
            let days = history.days.suffix(count)
            let summary = NutrientTrendSummary(days: days, nutrient: .sodium)
            XCTAssertEqual(days.count, count)
            XCTAssertEqual(days.map(\.date), days.map(\.date).sorted())
            XCTAssertEqual(summary.completedCount, completed)
            XCTAssertEqual(summary.visibleCount, 2)
            XCTAssertEqual(summary.average.sodium, 250)
            XCTAssertTrue(summary.average.estimated.contains(.sodium))
            XCTAssertEqual(summary.average.formatted(.sodium, forSpeech: true), "Approximately 250 mg")
        }
        let day = history.days[27]
        let contributions = day.contributions(for: .sodium)
        XCTAssertEqual(day.totals.sodium, 500)
        XCTAssertEqual(contributions.compactMap { $0.nutrition.sodium }.reduce(0, +), day.totals.sodium)
        XCTAssertEqual(contributions.first { $0.sourceName == "Other App" }?.contributionName, "Unnamed nutrition entry")
        XCTAssertEqual(contributions.first { $0.isFromTally }?.contributionName, "Food")
        XCTAssertEqual(history.readWindow(on: day, for: .sodium), .partial)
        XCTAssertEqual(history.readWindow(on: history.days[26], for: .sodium), .outside)
        XCTAssertNil(history.days[26].totals.sodium)
        XCTAssertEqual(history.days[28].contributions(for: .sodium).first?.nutrition.sodium, 0)
        XCTAssertEqual(history.today.totals.sodium, 800)
        let unavailable = NutrientTrendSummary(days: history.days.suffix(7), nutrient: .protein)
        XCTAssertEqual(unavailable.visibleCount, 0)
        XCTAssertNil(unavailable.average.protein)
    }

    func testAllSupportedNutrientsKeepTheirUnitsAndTotals() throws {
        let now = instant("2026-05-01T12:00:00Z")
        let previous = instant("2026-04-30T12:00:00Z")
        let nutrients = Nutrient.allCases
        let units = ["mg", "kcal", "g", "g", "g", "g", "g", "g", "mg"]
        let records = nutrients.map { sample($0, 12, previous) }
        let history = try NutritionHistorySnapshot(samples: records, ownBundle: "own", limitedDates: [:],
                                                   now: now, calendar: calendar(in: "UTC"))
        XCTAssertEqual(nutrients.map(\.unit), units)
        for nutrient in nutrients {
            let summary = NutrientTrendSummary(days: history.days.suffix(7), nutrient: nutrient)
            XCTAssertEqual(summary.average.formatted(nutrient), "12 \(nutrient.unit)")
            XCTAssertEqual(history.days[28].contributions(for: nutrient).count, 1)
            XCTAssertNil(history.today.totals[nutrient])
        }
    }

    // São Paulo advanced its clocks at midnight, so the affected local day starts at 01:00.
    func testMidnightClockChangeUsesActualStartOfEachDay() throws {
        let calendar = calendar(in: "America/Sao_Paulo")
        let now = instant("2018-11-05T12:00:00Z")
        let crossed = DateWindows.day(containing: instant("2018-11-04T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(crossed.start, instant("2018-11-04T03:00:00Z"))
        XCTAssertEqual(crossed.end, instant("2018-11-05T02:00:00Z"))
        XCTAssertEqual(DateWindows.recent(days: 3, now: now, calendar: calendar).start, instant("2018-11-03T03:00:00Z"))
        let history = try NutritionHistorySnapshot(samples: [
            sample(.caffeine, 12, crossed.end.addingTimeInterval(-1)),
            sample(.caffeine, 34, crossed.end)
        ], ownBundle: "own", limitedDates: [:], now: now, calendar: calendar)
        XCTAssertEqual(history.days[28].totals.caffeine, 12)
        XCTAssertEqual(history.today.totals.caffeine, 34)
    }

    @MainActor
    func testFailedRefreshRebucketsStaleDataAndHonoursNewlyRestrictedReads() async throws {
        let now = instant("2026-05-01T04:00:00Z")
        let date = instant("2026-05-01T00:30:00Z")
        let store = FakeNutritionStore()
        store.fixtureSamples = [sample(.protein, 17, date), sample(.caffeine, 55, date)]
        let manager = HealthKitManager(client: store, defaults: nil)
        try await manager.requestAccess()
        await manager.refresh(now: now, calendar: calendar(in: "UTC"))
        let original = try XCTUnwrap(manager.nutritionHistory)
        let key = original.dayKey(for: original.today.date)
        XCTAssertEqual(manager.today.protein, 17)

        store.queryError = HealthAccessError.unavailable
        store.readLimits = [.caffeine: now]
        await manager.refresh(now: now, calendar: calendar(in: "America/New_York"))
        let refreshed = try XCTUnwrap(manager.nutritionHistory)
        XCTAssertEqual(refreshed.dayKey(for: refreshed.today.date), key)
        XCTAssertEqual(manager.lastRefreshed, now)
        XCTAssertNotNil(manager.queryError)
        XCTAssertNil(manager.today.protein)
        XCTAssertEqual(refreshed.days[28].totals.protein, 17)
        XCTAssertEqual(refreshed.days[28].contributions(for: .protein).first?.nutrition.protein, 17)
        XCTAssertNil(refreshed.days[28].totals.caffeine)
        XCTAssertEqual(refreshed.readWindow(on: refreshed.days[28], for: .caffeine), .outside)

        store.readLimits = [:]
        await manager.refresh(now: now, calendar: calendar(in: "America/New_York"))
        XCTAssertNil(manager.nutritionHistory?.days[28].totals.caffeine)

        store.queryError = nil
        await manager.refresh(now: now.addingTimeInterval(60), calendar: calendar(in: "America/New_York"))
        XCTAssertNil(manager.queryError)
        XCTAssertEqual(manager.nutritionHistory?.days[28].totals.caffeine, 55)
        XCTAssertEqual(manager.lastRefreshed, now.addingTimeInterval(60))
    }

    private func sample(_ nutrient: Nutrient, _ value: Double, _ date: Date, source: String = "Tally",
                        name: String? = "Food", estimated: Bool = false) -> HealthSample {
        HealthSample(id: UUID(), nutrient: nutrient, value: value, date: date, sourceName: source,
                     sourceBundle: source == "Tally" ? "own" : "other", eventID: "shared id",
                     drinkName: name, isEstimated: estimated)
    }

    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func calendar(in timeZone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }
}
