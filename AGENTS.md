# AGENTS.md

Native iOS SwiftUI app for PATH train arrivals. All data logic lives in the local
package `Packages/PATHKit`; the app target `PATHStat` is a thin UI over it.

## Verified commands

Run from the repo root. Each was run and passed on Xcode 27.0 / Swift 6.4.

```sh
# Package tests (macOS, no network; live suite skipped)
swift test --package-path Packages/PATHKit

# Live check against the real PANYNJ feeds (network)
PATH_LIVE=1 swift test --package-path Packages/PATHKit --filter LiveFeedTests
swift run --package-path Packages/PATHKit path-live          # default GRV
swift run --package-path Packages/PATHKit path-live 33S      # any StationCode raw value

# Xcode project
xcodebuild -list -project PATHStat.xcodeproj
xcodebuild build -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17'       # runs PATHKitTests
```

`xcodebuild test` needs an installed iOS Simulator runtime; check with
`xcrun simctl list runtimes`. Pick a device name from
`xcodebuild -showdestinations -project PATHStat.xcodeproj -scheme PATHStat`.
Verified simulators: "iPhone 17" and "iPhone 18 Pro" (iOS 27.0 runtime).

If a simulator boot fails with "Unable to locate launchd_sim", run
`killall -9 com.apple.CoreSimulator.CoreSimulatorService` and retry.

## Conventions

- `PATHStat.xcodeproj/project.pbxproj` is hand-written (objectVersion 77). `PATHStat/` is a
  file-system synchronized group: new files under it join the target automatically, so add
  source files without editing the pbxproj. Edit the pbxproj only for build settings,
  targets, or package references, and re-run `xcodebuild -list` afterwards.
- No third-party dependencies, in the package or the app.
- Package is Swift 6 language mode; keep public types `Sendable`.
- Tests use Swift Testing (`import Testing`). Fixtures live in
  `Packages/PATHKit/Tests/PATHKitTests/Resources/` and load via `Bundle.module`;
  `makeFeed(...)` in `Support.swift` builds handcrafted feeds, `StubURLProtocol` stubs HTTP.
- Anything that touches the network belongs in `LiveFeedTests` (gated on `PATH_LIVE=1`).
- "toward X" means the train *stops at X after this station* on its identified line, in its
  direction — not that X is the terminus. Only an unidentified line falls back to `target == X`.
