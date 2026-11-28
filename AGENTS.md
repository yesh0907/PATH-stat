# AGENTS.md

Native iOS SwiftUI app for PATH train arrivals. All data logic lives in the local
package `Packages/PATHKit` (including the screen's `@MainActor @Observable BoardModel`, tested in
`BoardModelTests`); the app target `PATHStat` is a thin UI over it. `PATHStatWidget` is the
"Next PATH train" WidgetKit extension (Home Screen + Lock Screen), embedded in the app; its
timeline logic is PATHKit's `WidgetTimeline`, and it shares data with the app through the App
Group `group.com.yesh0907.PATHStat` (`TripStore.shared`, `SnapshotCache.shared`).

The smart trip rule (`TripPlanner.smartTrip`): at/without Grove St → Grove St → 33rd St;
everywhere else → home to Grove St (23rd St keeps the "Going home" preset name). The app
remembers the nearest station of the last fix as `TripStore.lastNearestStation` in the App
Group store — a station code only, never coordinates; the widget's "Smart (based on location)"
mode (the default, raw value `nearest`) uses it when it can't get a fix, and the
"Next PATH train" App Shortcut (`StartSmartTrainActivityIntent`) always uses it (an intent
doesn't request a fix). The direction control's two
quick picks come from `TripPlanner.quickDestinations` (at Grove: 33rd St + WTC; elsewhere
Grove St + one more); the board height is fixed — hidden skeleton behind loading/no-trains/
offline, invisible placeholder rows in the trains layout — so switching direction never moves
the Favorites section.

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
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PATHStatUITests/LiveActivityGalleryUITests    # Live Activity views, all states
```

### UI-test scenarios and screenshots

The app has deterministic modes for UI tests, previews and screenshots (`PATHStat/Scenario.swift`):
`-UITestScenario <loading|trains|singleTrain|noTrains|scheduleFallback|offline|locationDenied|offlineWithData>` and optional
`-UITestLocation <lat>,<lon>` (alone it implies `trains`) and `-UITestFeedback <sent|offline|noToken>`
(see "Feedback pipeline"). Scenario mode uses a stub feed, a
throwaway `TripStore` suite and fixed location state; it never creates `CLLocationManager`.
`offlineWithData` starts from a 3-minute-old `initialSnapshot` and every fetch fails, so the
`offline-banner` appears after the first refresh. `singleTrain` is `trains` with one run per
line, so Grove St → WTC has exactly one train and the `following-train-placeholder` /
`later-trains-placeholder` messages show. UI coverage also includes switching trips from
a favorite. `scheduleFallback` shows Grove St → WTC with an empty realtime board and a
sample timetable; `noTrains` still has no timetable.
`-WidgetGallery <live|stale|offline|unavailable|noTrains>` instead shows every widget family
(shared views from `PATHStatWidgetUI/`, fixed `WidgetTimeline` entries from PATHKit's sample
snapshots) on one screen, identifier `widget-gallery` (tiles: `widget-systemSmall`, ...).
`WidgetGalleryUITests` attaches `widget-gallery-<state>`. Scenario and gallery modes never
write the App Group cache or reload widget timelines (`WidgetSync` is live-only).
`-LiveActivityGallery <live|rolledOver|stale|offline|ended>` shows the shared Live Activity
views (`PATHStatWidgetUI/TrainActivityViews.swift`, samples from `TrainActivitySampleState`) on
one screen, identifier `live-activity-gallery` (`live-activity-lockscreen`,
`live-activity-compact`, `live-activity-minimal`, `live-activity-expanded`);
`LiveActivityGalleryUITests` attaches `live-activity-gallery-<state>`. It never touches
ActivityKit or the caches (its Refresh button is non-interactive).
Live Activity in scenario mode uses an in-memory `StubLiveActivityBackend`; add
`-LiveActivityBackend real` to drive real ActivityKit (manual checks only, never in UI tests).
`-LiveActivityDuration <seconds>` (a `UserDefaults` argument, key `LiveActivityDuration`)
overrides the 60-minute duration in both backends, e.g. `-LiveActivityDuration 90` to watch it
end. Background refresh (`BackgroundRefresh`) is live-only: any scenario/gallery argument
disables it.
UI tests find elements by accessibility identifier (`station-header`, `direction-control`
(the three-segment direction control: quick picks `destination-<CODE>` plus the
`more-destinations` menu), `favorite-<FROM>-<TO>`, `station-<CODE>`, `next-train`, `next-train-scheduled`,
`following-train`, `following-train-placeholder`, `later-trains`, `later-trains-placeholder`,
`offline-banner`, `state-loading`,
`live-activity-button` (start / "Switch to this trip"), `live-activity-status`,
`live-activity-stop`, `live-activity-error`, `live-activity-disabled`, `live-activity-settings`, ...);
keep identifiers stable when editing views.

In live mode PATHKit's `ScheduleRepository` downloads the
[Port Authority PATH GTFS schedule](https://www.panynj.gov/content/dam/path/gtfs/PATH_GTFS.zip)
and caches the last valid ZIP in the App Group (or caches directory without it). The app refreshes
it daily while active. The main board can show the next scheduled departure when no realtime
departure is available, including offline with a usable cached timetable. Widgets and Live
Activities still use only realtime data.

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

## Feedback pipeline

In-app feedback (shake or the top speech-bubble feedback button) becomes GitHub issues on `yesh0907/PATH-stat`.
Logic is in `Packages/PATHKit/Sources/PATHKit/Feedback/` (`FeedbackIssueFormatter`,
`GitHubClient`, `FeedbackQueue`, tested in `FeedbackFormatterTests`, `GitHubClientTests`,
`FeedbackQueueTests` with `StubURLProtocol.registerHost`); app glue is in `PATHStat/Feedback/`
(`FeedbackCenter`, `FeedbackSheet`, `FeedbackSettingsView`, `KeychainTokenStore`). Tests and
manual checks never call the real GitHub API and never use a real token.

- **Labels are a contract** with the daily 6:13 AM ET Devin triage automation: every issue the
  app creates has exactly `feedback` plus one of `bug`, `design-nit`, `frustration`, `idea`
  (colours in `GitHubClient.labelColors`). Lifecycle labels `devin-working`, `devin-shipped`,
  `design-proposed` and `needs-yesh` are set only by the automation. The owner-only labels
  `mockup-first` and `just-ship` override design triage. The app does not set these labels.
- **Title**: first non-empty note line, whitespace collapsed, ≤ 80 chars cut at a word with
  "…"; else `<Category> on <screen>`.
- **Body** (exact order, see `FeedbackIssueFormatter.body`): the full note or `_No note._`;
  blank line; `![Screenshot](<url>)` or `_No screenshot._`; blank line; `<details>` /
  `<summary>Context</summary>` with a `| Field | Value |` table (Category, App version, Git
  commit, iOS, Device, Screen, Trip, Station, Location permission, Feed updated, Feed age, Feed
  freshness, Last feed error, Recent notices, Live Activity, Appearance, Dynamic Type, Reported
  at (ISO 8601 UTC), Report ID); a ```` ```json ```` block with `FeedbackContext` (sorted keys,
  ISO 8601 dates); `</details>`; then `<!-- pathstat-feedback-id: <UUID> -->`. Parse the JSON
  block rather than the table. Context never contains coordinates or distances: location is
  only `locationPermission` and the station header word in `stationContext`. Changing the
  format breaks the automation; update `FeedbackFormatterTests` and this section together.
- **Screenshots** live on the orphan branch `feedback-assets` (README only, never merge it) at
  `screenshots/<yyyy-MM-dd UTC>/<report UUID>.png`, linked as
  `https://github.com/yesh0907/PATH-stat/blob/feedback-assets/<path>?raw=true`. Read them with
  `gh api repos/yesh0907/PATH-stat/contents/<path>?ref=feedback-assets` or by fetching that
  branch; they're visible to anyone who can read the repo.
- **Delivery**: `FeedbackQueue` (`Application Support/Feedback/pending/<id>.png` then
  `<id>.json`) keeps reports until the issue exists; backoff 30 s doubling to 1 h; retries on
  launch, foreground, network recovery, token save, `BackgroundRefresh.perform`, Retry now.
  The token is in the Keychain only (`com.yesh0907.PATHStat.feedback` / `github-token`); logs
  (category `feedback`) carry report IDs and outcomes only, never the token or note.
- **Reproducing a report**: read its context JSON, then launch with the matching scenario
  (`-UITestScenario …`, `-UITestLocation …` near the reported station), open the trip with
  `pathstat://trip?from=<FROM>&to=<TO>`, and set Appearance / Dynamic Type with `simctl ui`.
  `-UITestFeedback <sent|offline|noToken>` (default `sent`; alone it implies `trains`) runs
  feedback against an in-memory token and a stub service: `sent` returns issue #42, `offline`
  throws a network error, `noToken` has no token. Scenario mode adds a near-invisible 44×44
  `debug-simulate-shake` button ("Simulate shake", leading edge, own window above sheets) that
  posts the same `.pathStatDeviceDidShake` notification as a real shake.
- **Identifiers**: `send-feedback-button`, `feedback-settings-button` (a row in the feedback
  sheet, no longer on the main screen), `feedback-pending`,
  `feedback-sheet`, `feedback-screenshot`, `feedback-markup`, `feedback-remove-screenshot`
  (also "Add screenshot back"), `feedback-note`, `feedback-category-<bug|design-nit|frustration|idea>`,
  `feedback-cancel`, `feedback-send`, `feedback-share`, `feedback-sending`, `feedback-sent`,
  `feedback-issue-link`, `feedback-queued`, `feedback-queued-reason`, `feedback-queued-settings`,
  `feedback-done`;
  settings (presented from the sheet or the `feedback-pending` line): `feedback-settings`, `feedback-token-field`, `feedback-token-save`,
  `feedback-token-test`, `feedback-token-test-result`, `feedback-token-remove`, `feedback-retry`.

```sh
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PATHStatUITests/FeedbackUITests                # feedback sheet, shake, queue
```

The app's "Embed Git Commit" build phase (last phase, always runs, app target has
`ENABLE_USER_SCRIPT_SANDBOXING = NO`) writes `PATHStatGitCommit` (`git rev-parse --short=12`,
`-dirty`, or `unknown`) into the built Info.plist; check with
`plutil -p DD/Build/Products/Debug-iphonesimulator/PATHStat.app/Info.plist`.

## CI & Devin Cloud

The [CI workflow](https://github.com/yesh0907/PATH-stat/actions/workflows/ci.yml) runs
PATHKit package tests and unsigned iOS Simulator tests on GitHub-hosted macOS (code PRs always
run both in full; see `plan` for when they are skipped). Devin Cloud
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

Open the `.xcresult` bundles in Xcode or browse each shard's `attachments/` for UI-test screenshots
(each `attachments/manifest.json` maps exported files to human-readable test names). The
`pathstat-test-results` artifact is assembled by the gate job from per-job artifacts and uploaded on
success and failure (partial results included), laid out as:

```
pathstat-results-<shard>/Build.xcresult
pathstat-results-<shard>/Tests.xcresult
pathstat-results-<shard>/attachments/      # shard = core | feedback-a | feedback-b | galleries | other
```

Jobs (all in `.github/workflows/ci.yml`):

- `plan` (Linux, `.github/scripts/plan-ci.sh`): emits `disposition` (`full` | `docs` | `reuse`),
  `tree` (`git rev-parse HEAD^{tree}`) and, for `reuse`, `reuse_run_id`/`reuse_url`. The only job
  with additional API read permissions (`actions`, `pull-requests`). The planner uses the
  workflow token on pushes. Each API request has a 15-second timeout and errors select `full`.
- `package` (`PATHKit package tests`, macOS) and `tests` run only for `full`. Both first check
  that the checked-out tree equals the planned tree.
- `tests` (matrix, `xcode-27`, `fail-fast: false`): five shards, each with one simulator
  (`-parallel-testing-enabled NO`). CI prefers iPhone 18 Pro Max, iPhone 18 Pro, then iPhone 17
  for the layout checks. Each shard runs an unsigned `build-for-testing` into a local derived
  data path, then uses `simctl bootstatus -b` to boot and wait for the simulator.
  `test-without-building` uses the generated `.xctestrun` and retries failed tests once. Local builds
  avoid the multi-minute downloads observed when restoring Xcode compiler caches or transferring
  shared build products. The package job still caches PATHKit's SwiftPM build. Shards:
  - `core`: `PATHKitTests` + `PATHStatUITests/PATHStatUITests`
  - `feedback-a`: `testSendViaButton`, `testQueuedWithoutToken` and `testRemoveScreenshot`
    from `FeedbackUITests`
  - `feedback-b`: the remaining `FeedbackUITests` cases, including new cases
  - `galleries`: `WidgetGalleryUITests` + `LiveActivityGalleryUITests`
  - `other`: `-only-testing:PATHStatUITests` minus the `PATHStatUITests`, `FeedbackUITests`,
    `WidgetGalleryUITests` and `LiveActivityGalleryUITests` classes. It picks up interaction,
    layout and any new UI class automatically. A new class that should run in its own shard needs
    a new matrix entry and a matching `-skip-testing` line in `other`.
  Reproduce a shard locally with its selectors, e.g. the `other` shard: `xcodebuild test -project
  PATHStat.xcodeproj -scheme PATHStat -destination 'platform=iOS Simulator,name=iPhone 17'
  -only-testing:PATHStatUITests -skip-testing:PATHStatUITests/PATHStatUITests
  -skip-testing:PATHStatUITests/FeedbackUITests -skip-testing:PATHStatUITests/WidgetGalleryUITests
  -skip-testing:PATHStatUITests/LiveActivityGalleryUITests`.
  To rebalance the shards, edit the `selectors` in the matrix.
  Each shard uploads `pathstat-results-<shard>` (3-day retention, `overwrite: true` so a
  failed-job rerun replaces the same name) with the build and test bundles and attachments on
  success or failure. The test step prints UTC timestamps for entering the shell and for starting
  and finishing `xcodebuild`. Compare invocation time with Xcode's first
  `Test Suite ... started at` line for launch overhead. The step returns Xcode's exit code.
- `app` (Linux, name **`App build and simulator tests`** — the required check, keep the exact name):
  runs after `plan`, `package` and `tests`. For `full` it fails unless the plan, package job and
  every shard succeeded. For `docs` and `reuse` both macOS jobs must be skipped; `reuse` also
  writes a link to the qualifying run into the check summary (only verified skips link).
  For `full` it uploads `pathstat-test-results` (14 days, `overwrite: true`) even on failure, with
  whatever shard artifacts exist. On an all-green run it then requires every shard's
  `Build.xcresult`, `Tests.xcresult` and `attachments/manifest.json`. Keep `CI_SHARDS` equal to
  the matrix. A failed-job rerun includes earlier shard artifacts from the same run ID. If any
  expired (3 days), the gate fails and instructs you to re-run all jobs.
  For a same-repo PR into `main` only, after validation it uploads `pathstat-tested-tree-<run_attempt>`
  (14 days). Its `proof.json` records the tree, PR head and number, run ID and attempt,
  repository, base and aggregate artifact ID.

### Skipping CI after merge (`reuse`)

On a push to `main`, `plan` verifies all of the following before reusing PR results.

1. The push is a single non-forced update to `main` on the first-parent history
   (`event.before` equals `HEAD^1`).
2. GitHub associates the landed commit with exactly one matching merged PR from this repository
   into `main`. A docs-only diff selects `docs` here.
3. The latest matching `ci.yml` run for the PR's final branch and head SHA finished successfully,
   and the latest execution of every required job passed. A run with an empty PR association list
   still needs proof naming the merged PR. Earlier successful jobs can carry through a failed-job
   rerun.
4. That run has an unexpired proof artifact for its latest attempt and an unexpired aggregate.
   The proof must match the push's tree, the PR, the head SHA, the run ID and attempt, the repository,
   the base and the current aggregate ID. If the base moved and changed the tested tree,
   the full suite runs.

Direct pushes, multi-commit pushes, fork PRs and their merges, manual dispatches, missing or expired
proof, and lookup errors run the full suite. Only same-repository PRs can publish proof. Each macOS
job verifies its checkout against the planner's recorded tree before testing.

GitHub-owned actions are pinned to commit SHAs: `actions/checkout` v7.0.1, `actions/cache` v6.1.0 (package job only),
`actions/upload-artifact` v7.0.2, `actions/download-artifact` v8.0.2.

- On same-repository PRs and their qualifying merges, changes confined to root Markdown files,
  `docs/` and `screenshots/` skip both macOS jobs. The gate still reports success. The planner
  compares the PR merge commit to its first parent and the landed commit to its previous main commit.
- New PR runs cancel superseded runs on the same PR.

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
- ActivityKit calls live only in `PATHStatWidgetUI/TrainActivities.swift`; Live Activity
  content is planned by PATHKit's `TrainActivityPlanner`. The intents in
  `PATHStatWidgetUI/TrainActivityIntents.swift` are `LiveActivityIntent`s compiled into both
  targets, so they always perform in the app's process (including the Lock Screen Refresh
  button). `PATHStatWidgetUI/TripEntities.swift` holds `TripEntity`/`StationEntity` for both.
  Live Activity logs use `Logger(subsystem: "com.yesh0907.PATHStat", category: "liveactivity")`.
- Never log location or coordinates; feed errors go to `Logger(subsystem: "com.yesh0907.PATHStat", category: "feed")`.
- "toward X" means the train *stops at X after this station* on its identified line, in its
  direction — not that X is the terminus. Only an unidentified line falls back to `target == X`.
