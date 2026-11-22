import SwiftUI

/// A dated destination reads the current shared snapshot as Health refreshes.
struct NutrientTrendDay: Hashable {
    let nutrient: Nutrient
    let date: DateComponents
}

struct NutritionTrendsView: View {
    @Environment(HealthKitManager.self) private var health
    @Binding var nutrient: Nutrient
    @State private var range = TrendRange.week
    @State private var selectedDate: DateComponents?

    private enum TrendRange: Int, CaseIterable, Identifiable {
        case week = 7, month = 30
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                if !health.isAvailable || !health.permissionsRequested { HealthAccessCard() }
                if health.isLoading { ProgressView("Refreshing Apple Health") }
                HealthSnapshotRefreshNotice()
                if let history = health.nutritionHistory {
                    trend(history)
                    HealthReadNote(showLimitedWindow: false)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await health.refresh() }
        .onChange(of: range) { _, newRange in
            // Falling out of the shorter range returns selection to today.
            if let history = health.nutritionHistory, let selectedDate,
               !history.days.suffix(newRange.rawValue).contains(where: { history.dayKey(for: $0.date) == selectedDate }) {
                self.selectedDate = nil
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                Picker("Nutrient", selection: $nutrient) {
                    ForEach(Nutrient.displayOrder) { item in Text(item.title).tag(item) }
                }
            } label: {
                Label(nutrient.title, systemImage: "chevron.up.chevron.down").font(.headline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Nutrient")
            .accessibilityValue(nutrient.title)
            .accessibilityIdentifier("trendNutrient")

            Picker("Trend range", selection: $range) {
                ForEach(TrendRange.allCases) { item in Text("\(item.rawValue) days").tag(item) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func trend(_ history: NutritionHistorySnapshot) -> some View {
        let days = Array(history.days.suffix(range.rawValue))
        let selectedIndex = days.firstIndex { history.dayKey(for: $0.date) == selectedDate } ?? (days.count - 1)
        let selected = days[selectedIndex]
        let summary = NutrientTrendSummary(days: days[...], nutrient: nutrient)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Daily total", value: nutrient.unit).font(.subheadline.weight(.semibold))
                NutrientTrendChart(days: days, nutrient: nutrient, calendar: history.calendar, selectedIndex: selectedIndex) { index in
                    selectedDate = history.dayKey(for: days[index].date)
                }
                if !days.contains(where: { $0.totals[nutrient] != nil }) {
                    Text("No visible \(nutrient.title.lowercased()) in this range.").font(.subheadline)
                        .accessibilityIdentifier("trendEmpty")
                }
                Text("A dot marks a recorded zero. A gap means no value is visible.")
                    .font(.caption).foregroundStyle(.secondary)
                if days.contains(where: { history.readWindow(on: $0, for: nutrient) != .full }) {
                    Text("Apple Health shares a limited history for \(nutrient.title.lowercased()).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                selectedDay(selected, in: history, days: days)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 5) {
                Text("Daily average").font(.headline)
                Text(summary.average.formatted(nutrient) ?? "No average available")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel(summary.average.formatted(nutrient, forSpeech: true) ?? "No average available")
                    .accessibilityIdentifier("trendAverage")
                Text("\(summary.visibleCount) of \(summary.completedCount) completed days with data")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("trendCoverage")
                if summary.average.estimated.contains(nutrient) || selected.totals.estimated.contains(nutrient) {
                    Text("~ means estimated").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectedDay(_ selected: HistoryDay, in history: NutritionHistorySnapshot, days: [HistoryDay]) -> some View {
        let key = history.dayKey(for: selected.date)
        let selection = Binding(get: { key }, set: { selectedDate = $0 })
        let title = dayTitle(selected, in: history)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityIdentifier("trendSelectedDate")
            Text(selected.totals.formatted(nutrient) ?? "No visible data")
                .font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityLabel(selected.totals.formatted(nutrient, forSpeech: true) ?? "No visible data")
                .accessibilityIdentifier("trendSelectedTotal")
            NutritionReadWindowNote(window: history.readWindow(on: selected, for: nutrient))
            // The native day picker exposes every slot, including gaps that have no chart mark.
            Menu {
                Picker("Selected day", selection: selection) {
                    ForEach(days) { day in
                        let date = dayTitle(day, in: history)
                        let amount = day.totals.formatted(nutrient) ?? "No visible data"
                        let spokenAmount = day.totals.formatted(nutrient, forSpeech: true) ?? "No visible data"
                        Text("\(date), \(amount)")
                            .accessibilityLabel("\(date), \(spokenAmount)")
                            .tag(history.dayKey(for: day.date))
                    }
                }
            } label: {
                Label("Choose day", systemImage: "calendar")
            }
            .accessibilityValue(title)
            .accessibilityIdentifier("chooseTrendDay")
            NavigationLink("View contributions", value: NutrientTrendDay(nutrient: nutrient, date: key))
                .accessibilityIdentifier("viewTrendContributions")
        }
    }

    private func dayTitle(_ day: HistoryDay, in history: NutritionHistorySnapshot) -> String {
        let date = DateWindows.format(day.date, as: .dateTime.weekday(.abbreviated).day().month(.abbreviated),
                                      calendar: history.calendar)
        return day.date == history.today.date ? "\(date) · today so far" : date
    }
}
