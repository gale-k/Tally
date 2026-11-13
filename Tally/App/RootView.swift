import SwiftUI

/// Each tab owns its native navigation stack and keeps modal flows independent.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    ContentUnavailableView("A little more mindful", systemImage: "cup.and.saucer.fill",
                                           description: Text("Your everyday drinks, connected to Apple Health."))
                        .navigationTitle("Today")
                }
            }
            Tab("Drinks", systemImage: "cup.and.saucer") {
                NavigationStack {
                    ContentUnavailableView("Your usuals, all together", systemImage: "mug",
                                           description: Text("Save a drink once. Come back whenever you like."))
                        .navigationTitle("Drinks")
                }
            }
            Tab("History", systemImage: "clock") {
                NavigationStack { Text("Consumption history is read from Apple Health.").padding().navigationTitle("History") }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    Form { Text("Saved drinks stay on this device. Logged nutrition is saved to Apple Health.") }
                        .navigationTitle("Settings")
                }
            }
        }
    }
}
