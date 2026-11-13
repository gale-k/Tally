# Tally

A native, caffeine-first iPhone companion for saving your usual drinks and logging known nutrition to Apple Health.

Built with Swift 6, SwiftUI, SwiftData, HealthKit, and Swift Charts. No backend, accounts, analytics, or cloud library syncing.

## Development

Open `Tally.xcodeproj` in Xcode 27.0 or later. The app uses the installed iOS 27 SDK and requires iOS 27.0 or later. Select your own signing team if needed.

Reusable drink templates are stored locally in SwiftData. Actual consumption history belongs to Apple Health. Unknown nutritional values stay unknown; explicit zero values are supported.

All verification runs locally with isolated DerivedData under `/private/tmp`. No GitHub Actions workflow is configured.
