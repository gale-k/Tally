import SwiftUI
import SwiftData

/// A nil scheme follows changes to the device's appearance automatically.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Tally keeps one local container; optional CloudKit sync transfers only explicit template records. A store error is shown instead of discarding the library.
@main
struct TallyApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @State private var health: HealthKitManager
    @State private var sync: LibrarySyncManager?
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        #if DEBUG
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        // Hosted live checks must not open the real library, start its sync, reset preferences, or access Health.
        let usesTestData = uiTesting || ProcessInfo.processInfo.arguments.contains("--isolated-test-host")
        if uiTesting && !ProcessInfo.processInfo.arguments.contains("--preserve-preferences") {
            // UI-test presentation choices must not leak into the next test; normal device preferences are untouched.
            for key in ["showCalories", "showProtein", "showSugar", "showCaffeine", "showSodium", "appearance", "trendNutrient"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            for reference in DailyIntakeReference.all {
                UserDefaults.standard.removeObject(forKey: reference.valueKey)
                UserDefaults.standard.removeObject(forKey: reference.enabledKey)
            }
            // Exercise the upgrade path with the original caffeine and visibility keys only.
            if ProcessInfo.processInfo.arguments.contains("--legacy-daily-settings") {
                UserDefaults.standard.set(250.0, forKey: "dailyCaffeineTarget")
                UserDefaults.standard.set(false, forKey: "showSugar")
            }
        }
        _health = State(initialValue: usesTestData
                        ? HealthKitManager(client: FixtureNutritionStore(populated: ProcessInfo.processInfo.arguments.contains("--populated-health")), defaults: nil)
                        : HealthKitManager())
        #else
        let usesTestData = false
        _health = State(initialValue: HealthKitManager())
        #endif
        do {
            let configuration = ModelConfiguration("Tally", isStoredInMemoryOnly: usesTestData, cloudKitDatabase: .none)
            let created = try LibraryStore.container(configuration: configuration)
            created.mainContext.autosaveEnabled = false
            #if DEBUG
            if usesTestData && ProcessInfo.processInfo.arguments.contains("--seed-library") {
                try DevelopmentData.seed(in: created.mainContext, defaults: nil)
            }
            #endif
            _sync = State(initialValue: try LibrarySyncManager(context: created.mainContext, allowsCloudAccess: !usesTestData))
            container = created
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container, let sync {
                    RootView().modelContainer(container).environment(health).environment(sync).tint(Color.accentColor)
                } else {
                    ContentUnavailableView("Your library couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                                           description: Text(startupError ?? "Please reopen Tally to try again. Your library has not been reset."))
                        .padding()
                }
            }
            #if DEBUG
            .modifier(DevelopmentAppearance(appAppearance: appearance))
            #else
            .preferredColorScheme(appearance.colorScheme)
            #endif
        }
    }
}
