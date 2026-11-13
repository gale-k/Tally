import SwiftUI
import SwiftData

/// Tally has one local-only container. A store error is shown instead of discarding the library.
@main
struct TallyApp: App {
    private let container: ModelContainer?
    private let startupError: String?

    init() {
        do {
            let configuration = ModelConfiguration("Tally", cloudKitDatabase: .none)
            container = try ModelContainer(for: SavedDrink.self, configurations: configuration)
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().modelContainer(container).tint(.brown)
            } else {
                ContentUnavailableView("Your library couldn’t open", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Please reopen Tally to try again. Your library has not been reset."))
                    .padding()
            }
        }
    }
}
