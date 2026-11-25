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
    @Environment(\.locale) private var locale
    @State private var selected: HistoryEntrySheet?
    @State private var repeatError: String?

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
                        Button { selected = .details(event) } label: { HistoryEventRow(event: event) }
                            .buttonStyle(.plain)
                            // Revealing a row's actions cannot log another serving by itself.
                            .swipeActions(allowsFullSwipe: false) {
                                if event.canLogAgain {
                                    Button("Log Again", systemImage: "arrow.clockwise") {
                                        Task { await logAgain(event) }
                                    }.tint(.accentColor).disabled(health.isSaving)
                                }
                                if event.canModify {
                                    Button("Edit Quantity", systemImage: "pencil") { selected = .quantity(event) }
                                        .tint(.gray).disabled(health.isSaving)
                                }
                            }
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
        .sheet(item: $selected) { sheet in
            NavigationStack {
                switch sheet {
                case let .details(event):
                    HistoryEventDetail(event: event) { selected = .quantity(event) }
                case let .quantity(event):
                    HistoryQuantityEditor(event: event, locale: locale)
                }
            }
            #if DEBUG
                // Apply the UI test's appearance and Dynamic Type at the modal root.
                .modifier(DevelopmentAppearance())
            #endif
        }
        .errorAlert($repeatError, title: "Couldn’t log item again")
    }

    private func logAgain(_ event: ConsumptionEvent) async {
        guard !health.isSaving else { return }
        do {
            try await health.logAgain(event)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { repeatError = error.localizedDescription }
    }
}

// Distinct routes let list actions open the editor directly and let details hand off to the same editor.
private enum HistoryEntrySheet: Identifiable {
    case details(ConsumptionEvent), quantity(ConsumptionEvent)

    var id: String {
        switch self {
        case let .details(event): "details:\(event.id)"
        case let .quantity(event): "quantity:\(event.id)"
        }
    }
}

/// Display the snapshot's serving count alongside its name while retaining the existing one-serving labels.
struct HistoryEventName: View {
    @Environment(\.locale) private var locale
    let name: String
    let quantity: Double

    var body: some View {
        if quantity == 1 {
            Text(name)
        } else {
            let count = ServingQuantity.formatted(quantity, locale: locale)
            Text("\(name) ×\(count)").accessibilityLabel("\(name), \(count) servings")
        }
    }
}

struct HistoryEventRow: View {
    let event: ConsumptionEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HistoryEventName(name: event.name, quantity: event.quantity).font(.headline)
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

private struct HistoryEventDetail: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    let event: ConsumptionEvent
    let editQuantity: () -> Void
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                HistoryEventName(name: event.name, quantity: event.quantity).font(.title2.weight(.semibold))
                if let brand = event.brand { LabeledContent("Brand / Location", value: brand) }
                if let amount = event.servingAmount {
                    let formatted = amount.formatted(locale: locale)
                    let servingSize = event.size.flatMap { $0 == formatted ? nil : "\($0) · \(formatted)" } ?? formatted
                    LabeledContent("Serving size", value: servingSize)
                    if event.quantity != 1 {
                        LabeledContent("Total serving size", value: amount.formatted(quantity: event.quantity, locale: locale))
                    }
                } else if let size = event.size { LabeledContent("Serving size", value: size) }
                LabeledContent("Date", value: event.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Source", value: event.sourceName)
            }
            if event.canLogAgain || event.canModify {
                Section {
                    if event.canLogAgain {
                        Button("Log Again", systemImage: "arrow.clockwise") { Task { await logAgain() } }
                            .accessibilityIdentifier("historyLogAgain")
                            .accessibilityHint("Creates a new entry with this quantity")
                    }
                    if event.canModify {
                        Button("Edit Quantity", systemImage: "pencil", action: editQuantity)
                            .accessibilityIdentifier("historyEditQuantity")
                    }
                }.disabled(health.isSaving)
            }
            Section("Visible nutrition") { NutritionSummaryView(nutrition: event.nutrition) }
            if event.canModify {
                Section {
                    Button("Delete Entry", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .accessibilityIdentifier("historyDeleteEntry")
                        .disabled(health.isSaving)
                }
            }
            Section {
                Text("This record is read from Apple Health. Saved template edits and deletions never change this history. ~ means estimated.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Health Entry").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(health.isSaving) } }
            .interactiveDismissDisabled(health.isSaving)
            .confirmationDialog("Delete this consumption entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete from Apple Health", role: .destructive) { Task { await delete() } }
            } message: { Text("This removes the entry’s nutrition from Apple Health.") }
            .errorAlert($error, title: "Couldn’t update history")
    }

    private func logAgain() async {
        guard !health.isSaving else { return }
        do {
            try await health.logAgain(event)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        guard !health.isSaving else { return }
        do {
            try await health.delete(event)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// History edits preview the stored per-serving snapshot, so library changes cannot alter the calculation.
private struct HistoryQuantityEditor: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    let event: ConsumptionEvent
    let locale: Locale
    @State private var quantityText: String
    @State private var error: String?

    init(event: ConsumptionEvent, locale: Locale) {
        self.event = event
        self.locale = locale
        _quantityText = State(initialValue: ServingQuantity.formatted(event.quantity, locale: locale))
    }

    var body: some View {
        let quantity = ServingQuantity.parse(quantityText, locale: locale)
        let preview = quantity.flatMap { try? previewNutrition(for: $0) }
        Form {
            Section {
                Text(event.name).font(.title2.weight(.semibold))
                ServingQuantitySelector(text: $quantityText, amount: event.servingAmount, size: event.size)
                    .disabled(health.isSaving)
            }
            if let preview {
                Section("Nutrition") { NutritionSummaryView(nutrition: preview) }
            } else if quantity != nil {
                Section { Text("Choose a quantity that produces valid nutrition totals.").foregroundStyle(.secondary) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Quantity").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(health.isSaving) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let quantity, preview != nil else { return }
                    Task { await save(quantity) }
                }
                .disabled(health.isSaving || preview == nil || quantity == event.quantity)
                .accessibilityIdentifier("historySaveQuantity")
            }
        }
        .interactiveDismissDisabled(health.isSaving)
        .errorAlert($error, title: "Couldn’t edit quantity")
    }

    private func previewNutrition(for quantity: Double) throws -> NutritionValues {
        let draft = try event.withQuantity(quantity)
        try draft.validate()
        return draft.nutrition
    }

    private func save(_ quantity: Double) async {
        guard !health.isSaving else { return }
        do {
            try await health.updateQuantity(event, quantity: quantity)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
