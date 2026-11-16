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
    let nutrient: Nutrient
    private var title: String { nutrient == .sugar ? "Total Sugars" : nutrient.title }
    private var entries: [ConsumptionEvent] {
        health.todayEvents.filter { ($0.nutrition[nutrient] ?? 0) > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                if health.isLoading { ProgressView("Refreshing Apple Health") }
                if !health.isAvailable || !health.permissionsRequested { HealthAccessCard() }
                if let error = health.queryError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Health refresh needs attention", systemImage: "exclamationmark.circle").font(.headline)
                        Text(error)
                        Text("Any totals and entries still shown are from the last successful refresh.").font(.caption)
                        Button("Try Again") { Task { await health.refresh() } }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Today's visible total").font(.subheadline).foregroundStyle(.secondary)
                    Text(health.today.formatted(nutrient) ?? "No visible data")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .accessibilityIdentifier("contributionTotal")
                    if health.today.estimated.contains(nutrient) {
                        Text("~ means estimated").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HealthReadNote()
                if entries.isEmpty {
                    // A recorded zero is different from no visible Health sample at all.
                    Text(health.today[nutrient] == 0 ? "No entries increased this nutrient today." : "No contributing entries are visible today.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("contributionEmpty")
                } else {
                    Text("Contributing entries").font(.headline)
                    ForEach(entries) { event in
                        NutrientContributionRow(event: event, nutrient: nutrient)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await health.refresh() }
    }
}

/// Each positive event retains its historical name, source and nutrient-specific estimate marker.
private struct NutrientContributionRow: View {
    let event: ConsumptionEvent
    let nutrient: Nutrient
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.name).font(.headline)
                Spacer()
                Text(event.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if let brand = event.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
            if let amount = event.nutrition.formatted(nutrient) {
                Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("\(amount)\(event.nutrition.estimated.contains(nutrient) ? ", estimated" : "")")
            }
            Label(event.sourceName, systemImage: event.isFromTally ? "list.bullet.clipboard" : "heart")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
