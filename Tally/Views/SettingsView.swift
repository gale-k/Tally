import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Preferences are device-local. Read permissions stay private; only exposed write statuses are displayed.
struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var drinks: [SavedDrink]
    @AppStorage("showCalories") private var showCalories = true
    @AppStorage("showSugar") private var showSugar = true
    @AppStorage("showProtein") private var showProtein = true
    @AppStorage("showCaffeine") private var showCaffeine = true
    // Opt-in keeps the existing Today layout until sodium tracking is requested.
    @AppStorage("showSodium") private var showSodium = false
    @State private var requesting = false
    @State private var healthGuidance = false
    @State private var importing = false
    @State private var exporting = false
    @State private var document: DrinkLibraryDocument?
    @State private var error: String?
    @State private var importMessage: String?
    @State private var restoreCopies = false
    @State private var pendingRestore: Data?
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
                Toggle("Show Sodium", isOn: $showSodium)
            } header: { Text("Nutrition on Today") }
            footer: { Text("Choose the summaries you want to see. All nutrition remains available in templates, Quick Add, and history details.") }
            Section {
                NavigationLink("Daily Intake") { DailyIntakeSettingsView() }
                    .accessibilityIdentifier("dailyIntakeSettings")
            } footer: { Text("Adult references and personal targets for eight nutrients. Edit or turn off each daily comparison.") }
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

            CloudLibrarySection()
            Section {
                Button("Export Library Snapshot", systemImage: "square.and.arrow.up") {
                    do { document = DrinkLibraryDocument(data: try DrinkExportService.export(drinks)); exporting = true }
                    catch { self.error = error.localizedDescription }
                }
                Button("Import Library", systemImage: "square.and.arrow.down") { restoreCopies = false; importing = true }
                Button("Restore Snapshot as New Copies", systemImage: "clock.arrow.circlepath") { restoreCopies = true; importing = true }
            } header: { Text("Backups & Restore") }
            footer: { Text("Export creates an independent JSON snapshot. Choose iCloud Drive in Files to keep a recovery copy there. This is a manual backup, separate from live sync. Import adds missing templates and keeps existing ones unchanged. Health history is excluded.") }
            Section("About") {
                Label("Tally", systemImage: "list.bullet.clipboard.fill").font(.headline)
                Text("Saved templates are available on this device, with optional private iCloud sync. Logged nutrition is saved to Apple Health.")
                Text("No Tally account, advertising, analytics, or custom server.").font(.footnote).foregroundStyle(.secondary)
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
                let data = try DrinkExportService.readFile(url)
                if restoreCopies {
                    _ = try DrinkExportService.decode(data)
                    pendingRestore = data
                } else { importMessage = try DrinkExportService.importDrinks(data, into: context).message }
            } catch { if (error as NSError).code != NSUserCancelledError { self.error = "Couldn’t import this library. \(error.localizedDescription)" } }
        }
        // Capture the selected snapshot independently of the dialog dismissal lifecycle.
        .confirmationDialog("Restore Snapshot as New Copies?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible, presenting: pendingRestore) { data in
            Button("Restore Copies") {
                do { importMessage = try DrinkExportService.importDrinks(data, into: context, mode: .restoreCopies).message }
                catch { self.error = error.localizedDescription }
                pendingRestore = nil
            }
        } message: { _ in Text("Every template in this snapshot will be added as a new copy. You may see duplicates. Existing templates and Apple Health history will not be changed.") }
        .alert("Library imported", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("Done") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .errorAlert($error)
    }
    @MainActor private func requestAccess() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do { try await health.requestAccess() } catch { self.error = error.localizedDescription }
    }
}
