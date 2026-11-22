import Charts
import SwiftUI

/// Integer day slots keep equal spacing through clock changes and reserve space for gaps.
struct NutrientTrendChart: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let days: [HistoryDay]
    let nutrient: Nutrient
    let calendar: Calendar
    let selectedIndex: Int
    let select: (Int) -> Void

    private var selection: Binding<Double?> {
        Binding(get: { Double(selectedIndex) }, set: { position in
            // Swift Charts clears its gesture value at the end of a scrub; keep the selected day.
            guard let position else { return }
            let index = Int(position.rounded())
            if days.indices.contains(index) { select(index) }
        })
    }

    private var labelSlots: [Double] {
        if typeSize.isAccessibilitySize { return [0, Double(days.count - 1)] }
        if days.count == 7 { return days.indices.map(Double.init) }
        return [0, 7, 14, 21, Double(days.count - 1)]
    }

    var body: some View {
        Chart {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                if let total = day.totals[nutrient], let amount = day.totals.formatted(nutrient, forSpeech: true) {
                    let date = DateWindows.format(day.date, as: .dateTime.weekday(.wide).day().month(.wide), calendar: calendar)
                    if total == 0 {
                        PointMark(x: .value("Day", Double(index)), y: .value(nutrient.unit, 0.0))
                            .symbolSize(24)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(date)
                            .accessibilityValue("\(amount), recorded zero")
                    } else {
                        // Give each bar a fixed fraction of one slot, even in sparse 30-day ranges.
                        RectangleMark(xStart: .value("Day start", Double(index) - 0.34),
                                      xEnd: .value("Day end", Double(index) + 0.34),
                                      yStart: .value(nutrient.unit, 0.0), yEnd: .value(nutrient.unit, total))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(date)
                            .accessibilityValue(amount)
                    }
                }
            }
            RuleMark(x: .value("Selected day", Double(selectedIndex)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .chartXScale(domain: -0.5...(Double(days.count) - 0.5))
        .chartYScale(domain: 0...max(1, days.compactMap { $0.totals[nutrient] }.max() ?? 0),
                     range: .plotDimension(startPadding: 6, endPadding: 8))
        .chartXSelection(value: selection)
        .chartGesture { proxy in
            // A tap selects a slot while vertical drags still scroll the page at large text sizes.
            SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
        }
        .chartXAxis {
            AxisMarks(values: labelSlots) { value in
                AxisTick()
                if let index = value.as(Double.self).map(Int.init) {
                    AxisValueLabel(centered: false, anchor: axisAnchor(for: index)) {
                        Text(axisLabel(for: days[index].date)).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 3 : 4)) { value in
                AxisGridLine()
                if let amount = value.as(Double.self) {
                    AxisValueLabel { Text(amount.formatted(.number.notation(.compactName))).font(.caption2) }
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 200 : 168)
        .accessibilityLabel("\(nutrient.title) daily totals in \(nutrient.unit)")
        .accessibilityIdentifier("nutritionTrendChart")
    }

    // Keep the first and last date labels inside the chart, even at accessibility sizes.
    private func axisAnchor(for index: Int) -> UnitPoint {
        if index == 0 { return .topLeading }
        if index == days.count - 1 { return .topTrailing }
        return .top
    }

    private func axisLabel(for date: Date) -> String {
        let style: Date.FormatStyle = days.count == 7 && !typeSize.isAccessibilitySize
            ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated)
        return DateWindows.format(date, as: style, calendar: calendar)
    }
}
