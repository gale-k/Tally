import SwiftUI

/// Prominent buttons use an adaptive foreground to contrast with the light/dark accent.
/// Permission-sheet completion and readable data are intentionally different concepts in the UI.
/// Secondary grouped surfaces preserve rounded-card separation in dark appearance.
struct HealthAccessCard: View {
    @Environment(HealthKitManager.self) private var health
    @State private var requesting = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(health.isAvailable ? "Your nutrition, in Apple Health" : "Apple Health unavailable", systemImage: "heart.text.square")
                .font(.headline)
            Text(health.isAvailable ? "Choose which nutrition Tally can read and save. Your saved library stays available on this device." : "You can still create and organise saved foods and drinks on this device.")
                .font(.subheadline).foregroundStyle(.secondary)
            if health.isAvailable {
                Button {
                    requesting = true
                    Task {
                        defer { requesting = false }
                        do { try await health.requestAccess() } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack { if requesting { ProgressView() }; Text("Choose Health Access") }
                }.buttonStyle(.borderedProminent).foregroundStyle(Color(.systemBackground)).disabled(requesting).accessibilityIdentifier("chooseHealthAccess")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .errorAlert($error, title: "Health access needs attention")
    }
}

struct HealthReadNote: View {
    @Environment(HealthKitManager.self) private var health
    var showLimitedWindow = true
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Visible Apple Health nutrition · all sources")
            Text("Totals may include other apps and foods. Missing data can mean no entries or restricted read access.")
            if showLimitedWindow && !health.limitedDates.isEmpty {
                Text("Some nutrition has a limited history window. Only the dates Health allows are shown.")
            }
            if let refreshed = health.lastRefreshed { Text("Updated \(refreshed.formatted(date: .abbreviated, time: .shortened))") }
        }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Both Trends and its drill-down explain when their shared snapshot has become stale.
struct HealthSnapshotRefreshNotice: View {
    @Environment(HealthKitManager.self) private var health

    var body: some View {
        if let error = health.queryError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Health refresh needs attention", systemImage: "exclamationmark.circle").font(.headline)
                Text(error).font(.subheadline)
                if health.nutritionHistory != nil {
                    Text("Showing stale data from the last successful refresh.")
                        .font(.caption)
                        .accessibilityIdentifier("staleNutritionSnapshot")
                }
                Button("Try Again") { Task { await health.refresh() } }
            }
        }
    }
}

/// A known time-limited read window has its own explanation on affected days.
struct NutritionReadWindowNote: View {
    let window: NutritionHistorySnapshot.ReadWindow

    var body: some View {
        if window != .full {
            Text(window == .outside ? "Outside the Apple Health read window." : "Apple Health only shares part of this day.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
