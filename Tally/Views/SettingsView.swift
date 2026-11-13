import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Preferences are device-local. Read permissions stay private; only exposed write statuses are displayed.
struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var drinks: [SavedDrink]
    @AppStorage("dailyCaffeineTarget") private var target = 400.0
    @AppStorage("showCalories") private var showCalories = true
    @AppStorage("showSugar") private var showSugar = true
    @AppStorage("showProtein") private var showProtein = true
    @AppStorage("showCaffeine") private var showCaffeine = true
    @State private var targetText = "400"
    @State private var requesting = false
    @State private var healthGuidance = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document: DrinkLibraryDocument?
    @State private var error: String?
    @State private var importMessage: String?
    #if DEBUG
    @AppStorage(DevelopmentData.marker) private var developmentSeeded = false
    #endif

    var body: some View {
        Form {
            // General nutrition preferences lead; caffeine remains an optional personal tracking feature.
            Section {
                Toggle("Show Calories", isOn: $showCalories)
                Toggle("Show Protein", isOn: $showProtein)
                Toggle("Show Sugar", isOn: $showSugar)
                Toggle("Show Caffeine & Trend", isOn: $showCaffeine)
            } header: { Text("Nutrition on Today") }
            footer: { Text("Choose the summaries you want to see. All nutrition remains available in templates, Quick Add, and history details.") }
            Section {
                HStack {
                    Text("Daily target")
                    Spacer()
                    TextField("400", text: $targetText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .frame(maxWidth: 105).accessibilityLabel("Daily caffeine tracking target, milligrams")
                        .accessibilityIdentifier("dailyTarget")
                    Text("mg").foregroundStyle(.secondary)
                }
                Button("Update Target") { saveTarget() }
            } header: { Text("Caffeine Tracking") }
            footer: { Text("Your personal tracking target is \(target.formatted()) mg. This is a tracking preference, not a medically recommended maximum.") }
            Section {
                LabeledContent("Health data", value: health.isAvailable ? "Available" : "Unavailable")
                LabeledContent("Permissions requested", value: health.permissionsRequested ? "Yes" : "Not yet")
                if health.isAvailable {
                    DisclosureGroup("Nutrition write permissions") {
                        ForEach(Nutrient.allCases) { nutrient in LabeledContent(nutrient.title, value: health.writeStatus(for: nutrient).rawValue) }
                    }
                    Button {
                        Task { await requestAccess() }
                    } label: { HStack { Text("Review Permission Request"); if requesting { Spacer(); ProgressView() } } }
                        .disabled(requesting || health.isLoading)
                    Button("Manage Health Access") { healthGuidance = true }
                }
                if let queryError = health.queryError { Text(queryError).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Apple Health") }
            footer: { Text("Health keeps read permissions private. No visible samples can mean no data or restricted access. Allow every known nutrient when logging an item; otherwise nothing in that event is saved.") }

            Section {
                Button("Export Library", systemImage: "square.and.arrow.up") {
                    do { document = DrinkLibraryDocument(data: try DrinkExportService.export(drinks)); exporting = true }
                    catch { self.error = error.localizedDescription }
                }
                Button("Import Library", systemImage: "square.and.arrow.down") { importing = true }
            } header: { Text("Data") }
            footer: { Text("JSON contains saved templates and favourites only, never Apple Health history. Import adds missing items and leaves existing items unchanged.") }
            Section("About") {
                Label("Tally", systemImage: "list.bullet.clipboard.fill").font(.headline)
                Text("Saved foods and drinks are stored locally on this device. Logged nutrition is saved to Apple Health.")
                Text("No accounts, advertising, analytics, or Tally cloud syncing.").font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
            #if DEBUG
            Section {
                Button(developmentSeeded ? "Examples already added" : "Add Development Examples") {
                    do { try DevelopmentData.seed(in: context) } catch { self.error = error.localizedDescription }
                }.disabled(developmentSeeded)
            } header: { Text("Development") }
            footer: { Text("Debug builds only. Adds synthetic food and drink examples once, with all unknown nutrition blank. Never writes to Apple Health.") }
            #endif
        }
        .navigationTitle("Settings")
        .onAppear { targetText = target.formatted(.number.grouping(.never)) }
        .confirmationDialog("Manage Health Access", isPresented: $healthGuidance, titleVisibility: .visible) {
            Button("Review Permission Request") { Task { await requestAccess() } }
            Button("Open App Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
        } message: { Text("To change existing Health choices, open Health → your profile → Apps → Tally. Reviewing the request only shows a permission sheet if Health needs a new decision. App Settings opens the supported system settings page; Tally cannot toggle Health permissions for you.") }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Tally Library") { result in
            if case let .failure(error) = result, (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                importMessage = try DrinkExportService.importDrinks(DrinkExportService.readFile(url), into: context).message
            } catch { if (error as NSError).code != NSUserCancelledError { self.error = "Couldn’t import this library. \(error.localizedDescription)" } }
        }
        .alert("Library imported", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("Done") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .errorAlert($error)
    }
    private func saveTarget() {
        do {
            guard let value = try DrinkDraft.parse(targetText, nutrient: .caffeine), value >= 1 else {
                error = "Choose a personal tracking target from 1 to 10,000 mg."; return
            }
            target = value
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func requestAccess() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do { try await health.requestAccess() } catch { self.error = error.localizedDescription }
    }
}
