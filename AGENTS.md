# AGENTS.md

Native iOS SwiftUI app for PATH train arrivals. All data logic lives in the local
package `Packages/PATHKit` (including the screen's `@MainActor @Observable BoardModel`, tested in
`BoardModelTests`); the app target `PATHStat` is a thin UI over it. `PATHStatWidget` is the
"Next PATH train" WidgetKit extension (Home Screen + Lock Screen), embedded in the app; its
timeline logic is PATHKit's `WidgetTimeline`, and it shares data with the app through the App
Group `group.com.yesh0907.PATHStat` (`TripStore.shared`, `SnapshotCache.shared`).

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
  -destination 'platform=iOS Simulator,name=iPhone 17'       # PATHKitTests + PATHStatUITests (~3 min)
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PATHStatUITests                               # UI tests only
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PATHStatUITests/WidgetGalleryUITests          # widget views, all states
```

### UI-test scenarios and screenshots

The app has deterministic modes for UI tests, previews and screenshots (`PATHStat/Scenario.swift`):
`-UITestScenario <loading|trains|noTrains|offline|locationDenied|offlineWithData>` and optional
`-UITestLocation <lat>,<lon>` (alone it implies `trains`). Scenario mode uses a stub feed, a
throwaway `TripStore` suite and fixed location state; it never creates `CLLocationManager`.
`offlineWithData` starts from a 3-minute-old `initialSnapshot` and every fetch fails, so the
`offline-banner` appears after the first refresh. UI coverage also includes switching trips from
a favorite.
`-WidgetGallery <live|stale|offline|unavailable|noTrains>` instead shows every widget family
(shared views from `PATHStatWidgetUI/`, fixed `WidgetTimeline` entries from PATHKit's sample
snapshots) on one screen, identifier `widget-gallery` (tiles: `widget-systemSmall`, ...).
`WidgetGalleryUITests` attaches `widget-gallery-<state>`. Scenario and gallery modes never
write the App Group cache or reload widget timelines (`WidgetSync` is live-only).
UI tests find elements by accessibility identifier (`station-header`, `destination-<CODE>`,
`favorite-<FROM>-<TO>`, `station-<CODE>`, `next-train`, `offline-banner`, `state-loading`, ...);
keep identifiers stable when editing views.

```sh
# Export UI-test screenshots (each test attaches one, named after the test)
xcodebuild test ... -resultBundlePath /tmp/pathstat/Tests.xcresult
xcrun xcresulttool export attachments --path /tmp/pathstat/Tests.xcresult --output-path /tmp/pathstat/att
# manifest.json in the output maps exported files to `suggestedHumanReadableName`.

# Real app, live feed, simulated location (app built with -derivedDataPath DD)
UDID=$(xcrun simctl list devices available | grep -E '^ +iPhone 17 \(' | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $UDID; xcrun simctl bootstatus $UDID -b
xcrun simctl install $UDID DD/Build/Products/Debug-iphonesimulator/PATHStat.app
xcrun simctl privacy $UDID grant location com.yesh0907.PATHStat
xcrun simctl location $UDID set 40.7190,-74.0430        # near Grove St; 40.7432,-73.9925 near 23rd St
xcrun simctl launch $UDID com.yesh0907.PATHStat; sleep 6
xcrun simctl io $UDID screenshot shot.png
xcrun simctl ui $UDID appearance dark                     # reset: light
xcrun simctl ui $UDID content_size extra-extra-extra-large  # reset: large
xcrun simctl openurl $UDID 'pathstat://trip?from=HOB&to=WTC'  # deep link (shows a system confirm)
```

`simctl openurl` leaves an "Open in PATH Stat?" prompt that `simctl` can't dismiss. While it
is up, the app's `scenePhase` is not `.active`, so the refresh loop never starts and UI tests
time out showing "Loading trains…". Before running UI tests, go to the home screen, or
`xcrun simctl shutdown $UDID` and boot it again.

`xcodebuild test` needs an installed iOS Simulator runtime; check with
`xcrun simctl list runtimes`. Pick a device name from
`xcodebuild -showdestinations -project PATHStat.xcodeproj -scheme PATHStat`.
Verified simulators: "iPhone 17" and "iPhone 18 Pro" (iOS 27.0 runtime).

If a simulator boot fails with "Unable to locate launchd_sim", run
`killall -9 com.apple.CoreSimulator.CoreSimulatorService` and retry.

## Live simulator checks

For manual or visual checks — widgets on the Home/Lock Screen, Live Activity and Dynamic Island, permission prompts, deep links, before/after screenshots — drive a live iOS 27 simulator with [`agent-device`](https://agent-device.dev) instead of writing throwaway UI tests. XCUITests are for regression coverage only; never rebuild a UI test 3+ times just to reach a system screen.

- Get a booted simulator with your fresh build installed (`xcrun simctl install`; use `-UITestScenario …` for deterministic screens). In Up.computer, `device_open` boots one and returns the pinned `agent-device` command.
- Drive it: open the app, act on elements by ref/accessibility id, and verify with assertions (`wait text`, `is`) — a screenshot alone isn't verification. Keep screenshots as evidence in the PR or task output.
- Usage guide: the agent-device skill — https://github.com/callstack/agent-device/blob/main/skills/agent-device/SKILL.md (iOS-specific: https://github.com/callstack/agent-device/blob/main/skills/ios-simulator/SKILL.md).

## CI & Devin Cloud

The [CI workflow](https://github.com/yesh0907/PATH-stat/actions/workflows/ci.yml) runs
PATHKit package tests and unsigned iOS Simulator tests on GitHub-hosted macOS. Devin Cloud
sessions must get a green CI run for the latest PR commit before merging. CI uses the stubbed
UI scenarios with `PATH_LIVE` unset. Only local agents can run the live simulator against the
real PATH feeds.

From the repository root, find the run ID for your commit, read both job results, and download
the app test artifacts:

```sh
gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)"
gh run view <run-id>
gh run view <run-id> --log-failed
gh run download <run-id> --name pathstat-test-results --dir /tmp/pathstat-ci
```

Open `Tests.xcresult` in Xcode or browse `attachments/` for UI-test screenshots. The
`attachments/manifest.json` file maps the exported files to their human-readable test names.
CI uploads the bundle and attachments on success and failure when Xcode produces them.

## Signing (hard rule)

- Every PATH-stat target (app, widget, Live Activity extensions) uses automatic signing with
  `DEVELOPMENT_TEAM = 63L4D2UQLD` ("Yesh Chandiramani (Personal Team)", free).
- Never set any other team, and never register bundle IDs, devices, App Groups, capabilities,
  certificates or profiles under another team (e.g. an employer team). No TestFlight/App Store.
- Free personal teams lack some capabilities (e.g. APNs push); design around them.
- No TestFlight/App Store, and no APNs push: the user is on a free Personal Team (installed
  builds expire after 7 days). These limits lift only once the user sets up their own paid
  individual account — never by using any other team.
- The widget extension (`com.yesh0907.PATHStat.PATHStatWidget`) uses the same team. The App
  Group `group.com.yesh0907.PATHStat` (in `PATHStat/PATHStat.entitlements` and
  `PATHStatWidget/PATHStatWidget.entitlements`) must only ever be registered under
  `63L4D2UQLD`. Code must keep working without it (`TripStore.shared` / `SnapshotCache.shared`
  fall back to standard defaults / the caches directory).
- Never pass `-allowProvisioningUpdates`; build for the Simulator only unless the user asks.

## Conventions

- `PATHStat.xcodeproj/project.pbxproj` is hand-written (objectVersion 77). `PATHStat/` and
  `PATHStatUITests/` are file-system synchronized groups: new files under them join their
  target automatically, so add source files without editing the pbxproj.
  `PATHStatWidget/` (extension) and `PATHStatWidgetUI/` (shared widget views, `Color+Hex.swift`)
  are synchronized groups too; `PATHStatWidgetUI/` is a member of both the app and the widget
  target, so code there must compile in both (views take `family: WidgetFamily` explicitly).
  `PATHStat/Info.plist` (URL scheme `pathstat`) is excluded from the app's membership via an
  exception set and merged through `INFOPLIST_FILE`; other Info keys use `INFOPLIST_KEY_*`.
  Likewise `PATHStatWidget/Info.plist` (`NSExtension`, `NSWidgetWantsLocation`) and both
  `.entitlements` files are excluded from membership. Edit the pbxproj only for build settings,
  targets, or package references, and re-run `xcodebuild -list` afterwards.
- No third-party dependencies, in the package or the app.
- Package is Swift 6 language mode; keep public types `Sendable`.
- Tests use Swift Testing (`import Testing`). Fixtures live in
  `Packages/PATHKit/Tests/PATHKitTests/Resources/` and load via `Bundle.module`;
  `makeFeed(...)` in `Support.swift` builds handcrafted feeds, `StubURLProtocol` stubs HTTP.
- Anything that touches the network belongs in `LiveFeedTests` (gated on `PATH_LIVE=1`).
- UI tests are XCTest (required for XCUIApplication) and must use scenario mode, never the live feed.
- Put pure logic (trip planning, filtering, persistence) in PATHKit with tests; keep the app thin.
- Widget countdowns must stay correct without reloads: `Text(timerInterval:countsDown:)`,
  `Text(date, style: .time/.relative)`, never a precomputed minute count or `.timer` style.
- Never log location or coordinates; feed errors go to `Logger(subsystem: "com.yesh0907.PATHStat", category: "feed")`.
- "toward X" means the train *stops at X after this station* on its identified line, in its
  direction — not that X is the terminus. Only an unidentified line falls back to `target == X`.
