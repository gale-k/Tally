import SwiftUI

enum HistorySection: String, CaseIterable, Identifiable {
    case entries = "Entries", trends = "Trends"
    var id: Self { self }
}

struct HistoryView: View {
    @Binding var section: HistorySection
    @Binding var nutrient: Nutrient

    var body: some View {
        VStack(spacing: 0) {
            // The switch stays in view when scrolling either History surface.
            Picker("History view", selection: $section) {
                ForEach(HistorySection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            switch section {
            case .entries: HistoryEntriesView()
            case .trends: NutritionTrendsView(nutrient: $nutrient)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("History")
    }
}

/// Each day's totals include exactly its visible samples; only Tally-owned samples are reconstructed as multi-nutrient events.
private struct HistoryEntriesView: View {
    @Environment(HealthKitManager.self) private var health
    @State private var selected: ConsumptionEvent?
    var body: some View {
        List {
            Section {
                if !health.permissionsRequested || !health.isAvailable { HealthAccessCard().listRowInsets(EdgeInsets()) }
                Text("Last 30 days").font(.headline)
                HealthReadNote()
                if let error = health.queryError { Label(error, systemImage: "exclamationmark.circle").font(.footnote) }
            }
            ForEach(health.historyDays) { day in
                Section {
                    ForEach(day.events) { event in
                        Button { selected = event } label: { HistoryEventRow(event: event) }.buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Text(day.totals.summaryText).font(.caption).textCase(nil)
                    }
                }
            }
            if health.historyDays.isEmpty {
                ContentUnavailableView(health.isLoading ? "Reading Apple Health…" : "No visible nutrition yet", systemImage: "clock",
                                       description: Text("Log food or a drink, pull to refresh, or review Tally’s read permissions in Health. An empty result doesn’t tell us whether read access was granted."))
                    .listRowBackground(Color.clear)
            }
        }
        .refreshable { await health.refresh() }
        .toolbar { if health.isLoading { ProgressView() } }
        .sheet(item: $selected) { event in NavigationStack { HistoryEventDetail(event: event) } }
    }
}

struct HistoryEventRow: View {
    let event: ConsumptionEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.name).font(.headline)
                Spacer()
                Text(event.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if let brand = event.brand { Text(brand).font(.subheadline).foregroundStyle(.secondary) }
            Text(event.nutrition.summaryText).font(.subheadline).monospacedDigit()
            Label(event.sourceName, systemImage: event.isFromTally ? "list.bullet.clipboard" : "heart")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct HistoryEventDetail: View {
    let event: ConsumptionEvent
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text(event.name).font(.title2.weight(.semibold))
                if let brand = event.brand { LabeledContent("Brand / Location", value: brand) }
                if let size = event.size { LabeledContent("Serving size", value: size) }
                LabeledContent("Date", value: event.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Source", value: event.sourceName)
            }
            Section("Visible nutrition") { NutritionSummaryView(nutrition: event.nutrition) }
            Section {
                Text("This record is read from Apple Health. Saved template edits and deletions never change this history. ~ means estimated.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Health Entry").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
