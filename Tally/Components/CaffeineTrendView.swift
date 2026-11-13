import SwiftUI
import Charts

/// Missing read data produces gaps, not invented zero-consumption days.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct CaffeineTrendView: View {
    let days: [CaffeineDay]
    @State private var selectedDate: Date?
    private var selected: CaffeineDay? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text("Caffeine · mg").font(.caption).foregroundStyle(.secondary)
            }
            if days.contains(where: { $0.total != nil }) {
                Chart {
                    ForEach(days) { day in
                        if let total = day.total {
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Caffeine", total))
                                .foregroundStyle(Color.accentColor).cornerRadius(5)
                                .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(day.isEstimated ? "Approximately " : "")\(total.formatted()) milligrams")
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Selected day", selected.date, unit: .day)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { value in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 150)
                if let selected {
                    Text("\(selected.date.formatted(.dateTime.weekday(.wide))) · \(selected.total.map { "\(selected.isEstimated ? "~" : "")\($0.formatted()) mg" } ?? "No visible data")")
                        .font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently)
                }
            } else {
                Text("Your caffeine trend will appear as data becomes visible in Apple Health.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            }
            Text("Visible data from all sources. Days without visible samples have no bar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
