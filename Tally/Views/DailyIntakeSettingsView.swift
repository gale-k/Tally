import SwiftUI

/// Native navigation keeps nine editable comparisons compact and usable with larger text.
struct DailyIntakeSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(DailyIntakeReference.all) { reference in DailyIntakeSettingRow(reference: reference) }
            } header: { Text("UK Adult Reference Preset") }
            footer: { Text("General adult starting points; individual needs vary. Edit, disable, or reset each comparison. Changes stay on this device and never change logging, Health permissions, or nutrition history.") }
            DailyIntakeGuidance()
        }
        .navigationTitle("Daily Intake")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// AppStorage observes the same individual keys on Today and Settings, including legacy caffeine.
private struct DailyIntakeSettingRow: View {
    let reference: DailyIntakeReference
    @AppStorage private var value: Double
    @AppStorage private var enabled: Bool
    init(reference: DailyIntakeReference) {
        self.reference = reference
        _value = AppStorage(wrappedValue: reference.defaultValue, reference.valueKey)
        _enabled = AppStorage(wrappedValue: true, reference.enabledKey)
    }
    var body: some View {
        NavigationLink {
            DailyIntakeEditor(reference: reference, value: $value, enabled: $enabled)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(reference.title)
                Text(enabled ? "\(value.formatted()) \(reference.nutrient.unit) · \(reference.label(for: value))" : "Comparison off")
                    .font(.caption).foregroundStyle(.secondary)
                if enabled && reference.nutrient == .sodium { Text("Equivalent to \(reference.saltEquivalent(value))").font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityIdentifier("dailyIntake.\(reference.nutrient.rawValue)")
    }
}

/// Numeric edits remain a draft until Save succeeds; switching off retains the stored number.
private struct DailyIntakeEditor: View {
    let reference: DailyIntakeReference
    @Binding var value: Double
    @Binding var enabled: Bool
    @State private var text = ""
    @State private var error: String?
    @State private var saved = false
    @State private var sodiumUnit: SodiumInputUnit = .sodium
    @FocusState private var editing: Bool
    var body: some View {
        Form {
            Section {
                Toggle("Show daily comparison", isOn: $enabled).accessibilityIdentifier("comparisonEnabled")
                if reference.nutrient == .sodium {
                    // Convert the current draft on unit changes; invalid drafts remain untouched for correction.
                    Picker("Enter as", selection: Binding(get: { sodiumUnit }, set: { newUnit in changeUnit(to: newUnit) })) {
                        ForEach(SodiumInputUnit.allCases) { unit in Text("\(unit.title) (\(unit.unit))").tag(unit) }
                    }.accessibilityIdentifier("dailySodiumUnit")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily value (\(displayUnit))")
                    TextField("Daily value", text: $text).keyboardType(.decimalPad).focused($editing)
                        .accessibilityLabel("\(reference.title) daily value, \(displayUnit)")
                        .accessibilityIdentifier("dailyIntakeValue")
                        .onChange(of: text) { _, _ in saved = false }
                }
                Button("Save Value") {
                    do { value = try reference.parse(text, sodiumUnit: sodiumUnit); error = nil; saved = true; editing = false }
                    catch { self.error = error.localizedDescription; saved = false }
                }.accessibilityIdentifier("saveDailyIntake")
                if let error { Text(error).foregroundStyle(.primary).accessibilityIdentifier("dailyIntakeError") }
                if saved { Label("Value saved", systemImage: "checkmark.circle") }
                if reference.nutrient == .sodium { Text("Saved equivalent: \(reference.saltEquivalent(value))").font(.caption) }
                Button("Reset to Adult Default") {
                    value = reference.defaultValue; enabled = true
                    text = formattedValue; error = nil; saved = true; editing = false
                }.accessibilityIdentifier("resetDailyIntake")
            } footer: {
                Text("Saved: \(value.formatted()) \(reference.nutrient.unit) · \(reference.label(for: value)). Reset restores \(reference.defaultValue.formatted()) \(reference.nutrient.unit) and turns this comparison on. Turning it off never hides or discards nutrition data.")
            }
            DailyIntakeGuidance()
        }
        .navigationTitle(reference.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = formattedValue }
        .scrollDismissesKeyboard(.interactively)
    }
    private var displayUnit: String { reference.nutrient == .sodium ? sodiumUnit.unit : reference.nutrient.unit }
    private func changeUnit(to unit: SodiumInputUnit) {
        guard unit != sodiumUnit else { return }
        do {
            let canonical = try reference.parse(text, sodiumUnit: sodiumUnit)
            sodiumUnit = unit
            text = (canonical / unit.sodiumMultiplier).formatted(.number.grouping(.never).precision(.significantDigits(1...15)))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private var formattedValue: String {
        (value / (reference.nutrient == .sodium ? sodiumUnit.sodiumMultiplier : 1)).formatted(.number.grouping(.never).precision(.significantDigits(1...15)))
    }
}

/// Source links and the sugar distinction stay next to the settings they explain.
struct DailyIntakeGuidance: View {
    var body: some View {
        Section("About the Comparisons") {
            Text("Daily targets and maximums are tracking comparisons, not personalised advice. Food-label defaults are general adult references, not universal targets or safe maximums. Sugar and fat maximums are tracking choices based on those references. Protein and fibre are not upper limits.")
            Text("Total sugars includes naturally occurring sugars. Tally cannot separate free sugars; the NHS 30 g free-sugars guidance is not a limit for this total.")
            Text("The 400 mg caffeine starting value reflects general healthy-adult daily guidance. It is not suitable for everyone; pregnancy and breastfeeding have different guidance. Your saved caffeine value is retained.")
            Text("The adult sodium maximum starts at 2,400 mg, equivalent to 6 g salt. Individual needs vary.")
            Link("Food Standards Scotland · Salt and sodium", destination: URL(string: "https://www.foodstandards.gov.scot/consumer-advice/healthy-eating/balanced-diet/understanding-nutrients/salt")!)
            Link("NHS Scotland · Adult reference intakes", destination: URL(string: "https://mydiabetesmyway.scot.nhs.uk/resources/internal/food-labels/#reference-intakes")!)
            Link("Food Standards Scotland · Fibre", destination: URL(string: "https://www.foodstandards.gov.scot/consumer-advice/healthy-eating/balanced-diet/understanding-nutrients/fibre")!)
            Link("EFSA · Caffeine guidance", destination: URL(string: "https://www.efsa.europa.eu/en/topics/topic/caffeine")!)
            Link("NHS · Free and total sugars", destination: URL(string: "https://www.nhs.uk/live-well/eat-well/food-types/how-does-sugar-in-our-diet-affect-our-health/")!)
        }.font(.subheadline)
    }
}
