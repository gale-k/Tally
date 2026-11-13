import SwiftUI
import SwiftData

/// Tally has one local-only container. A store error is shown instead of discarding the library.
@main
struct TallyApp: App {
    @State private var health: HealthKitManager
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        #if DEBUG
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if uiTesting {
            // UI-test presentation choices must not leak into the next test; normal device preferences are untouched.
            for key in ["showCalories", "showProtein", "showSugar", "showCaffeine"] { UserDefaults.standard.removeObject(forKey: key) }
        }
        _health = State(initialValue: uiTesting
                        ? HealthKitManager(client: FixtureNutritionStore(populated: ProcessInfo.processInfo.arguments.contains("--populated-health")), defaults: nil)
                        : HealthKitManager())
        #else
        let uiTesting = false
        _health = State(initialValue: HealthKitManager())
        #endif
        do {
            let configuration = ModelConfiguration("Tally", isStoredInMemoryOnly: uiTesting, cloudKitDatabase: .none)
            let created = try ModelContainer(for: SavedDrink.self, configurations: configuration)
            created.mainContext.autosaveEnabled = false
            #if DEBUG
            if uiTesting && ProcessInfo.processInfo.arguments.contains("--seed-library") {
                try DevelopmentData.seed(in: created.mainContext, defaults: nil)
            }
            #endif
            container = created
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                #if DEBUG
                RootView().modelContainer(container).environment(health).tint(Color.accentColor).modifier(DevelopmentAppearance())
                #else
                RootView().modelContainer(container).environment(health).tint(Color.accentColor)
                #endif
            } else {
                ContentUnavailableView("Your library couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Please reopen Tally to try again. Your library has not been reset."))
                    .padding()
            }
        }
    }
}
