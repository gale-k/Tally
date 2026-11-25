import SwiftUI

/// The same card remains the navigation label on both daily summary surfaces.
struct NutrientContributionLink: View {
    let nutrient: Nutrient
    let nutrition: NutritionValues
    var fillRow = false
    var alignedStatusHeight: CGFloat?

    var body: some View {
        NavigationLink {
            NutrientContributionsView(nutrient: nutrient)
        } label: {
            SecondaryNutritionCard(nutrient: nutrient, nutrition: nutrition, fillRow: fillRow,
                                   alignedStatusHeight: alignedStatusHeight)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows today's contributing entries")
        .accessibilityIdentifier("nutrientContributions.\(nutrient.rawValue)")
    }
}

/// Entries and total come from the same successful Health refresh, never from editable templates.
struct NutrientContributionsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.openNutritionTrends) private var openNutritionTrends
    let nutrient: Nutrient
    var dateKey: DateComponents? = nil

    private var title: String { nutrient == .sugar ? "Total Sugars" : nutrient.title }
    private var calendar: Calendar { health.nutritionHistory?.calendar ?? .current }
    private var day: HistoryDay? {
        guard let history = health.nutritionHistory else { return nil }
        guard let dateKey else { return history.today }
        return history.days.first { history.dayKey(for: $0.date) == dateKey }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let date = day?.date ?? (dateKey == nil ? .now : dateKey.flatMap { calendar.date(from: $0) }) {
                    Text(DateWindows.format(date, as: .dateTime.weekday(.wide).day().month(.wide), calendar: calendar))
                        .font(.subheadline)
                }
                if health.isLoading { ProgressView("Refreshing Apple Health") }
                if !health.isAvailable || !health.permissionsRequested { HealthAccessCard() }
                HealthSnapshotRefreshNotice()
                Button { openNutritionTrends(nutrient) } label: { Label("View trend", systemImage: "chart.bar") }
                    .accessibilityIdentifier("openNutrientTrend")
                if !health.isLoading || health.nutritionHistory != nil { breakdown }
                HealthReadNote()
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await health.refresh() }
    }

    private var breakdown: some View {
        let entries = day?.contributions(for: nutrient) ?? []
        let isToday = dateKey == nil || (day != nil && day?.date == health.nutritionHistory?.today.date)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(isToday ? "Visible total · today so far" : "Visible total").font(.subheadline).foregroundStyle(.secondary)
                Text(day?.totals.formatted(nutrient) ?? "No visible data")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(day?.totals.formatted(nutrient, forSpeech: true) ?? "No visible data")
                    .accessibilityIdentifier("contributionTotal")
                if day?.totals.estimated.contains(nutrient) == true {
                    Text("~ means estimated").font(.caption).foregroundStyle(.secondary)
                }
                if let day, let history = health.nutritionHistory {
                    NutritionReadWindowNote(window: history.readWindow(on: day, for: nutrient))
                }
            }
            if entries.isEmpty {
                Text(isToday ? "No contributing entries are visible today." : "No contributing entries are visible for this day.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("contributionEmpty")
            } else {
                Text("Contributing entries").font(.headline)
                ForEach(entries) { event in
                    NutrientContributionRow(event: event, nutrient: nutrient, calendar: calendar)
                }
            }
        }
    }
}

/// Each visible entry retains its historical name, source and nutrient-specific estimate marker.
private struct NutrientContributionRow: View {
    let event: ConsumptionEvent
    let nutrient: Nutrient
    let calendar: Calendar
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name.fixedSize()
                    Spacer()
                    time.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) { name; time }
            }
            if let brand = event.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
            if let amount = event.nutrition.formatted(nutrient) {
                Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(event.nutrition.formatted(nutrient, forSpeech: true) ?? amount)
            }
            Label(event.sourceName, systemImage: event.isFromTally ? "list.bullet.clipboard" : "heart")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var name: some View { HistoryEventName(name: event.contributionName, quantity: event.quantity).font(.headline) }
    private var time: some View {
        Text(DateWindows.format(event.date, as: .dateTime.hour().minute(), calendar: calendar))
            .font(.caption).foregroundStyle(.secondary)
    }
}
