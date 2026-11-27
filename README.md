# PATH-stat

A native iOS (SwiftUI) app for real-time PATH train arrivals. Phase 1 is the data layer:
`PATHKit`, a pure Foundation + CoreLocation Swift package, plus a placeholder app screen that
lists the next trains at Grove Street in both directions, and a macOS debug CLI.

## Data sources

Both endpoints are public, unauthenticated JSON published by the Port Authority (PANYNJ).

### Realtime arrivals

`GET https://www.panynj.gov/bin/portauthority/ridepath.json`

```text
results[]
  consideredStation   station code, e.g. "GRV"
  destinations[]
    label             "ToNY" | "ToNJ"
    messages[]
      target              terminus station code, e.g. "33S"
      secondsToArrival    STRING, e.g. "25"
      arrivalTimeMessage  e.g. "1 min"
      lineColor           hex, or comma list for combined services ("4D92FB,FF9900")
      headSign            e.g. "33rd Street via Hoboken"
      lastUpdated         ISO-8601 with 6-digit fraction + offset, "2026-11-26T20:44:02.212216-05:00"
```

A train's arrival time is `lastUpdated + secondsToArrival`. Lines are identified by colour:

| Line | Colour | Stops (NJ → NY) |
|---|---|---|
| Newark–WTC | `D93A30` | NWK HAR JSQ GRV EXP WTC |
| Hoboken–WTC | `65C100` | HOB NEW EXP WTC |
| Journal Square–33rd St | `FF9900` | JSQ GRV NEW CHR 09S 14S 23S 33S |
| Hoboken–33rd St | `4D92FB` | HOB CHR 09S 14S 23S 33S |
| Journal Square–33rd St via Hoboken | `4D92FB,FF9900` | JSQ GRV NEW HOB CHR 09S 14S 23S 33S |

`toward: X` keeps trains that stop at X later on their line, in their direction. A short-turned
train (its `target` is on its line but before the line's end, e.g. a Newark–WTC train ending at
JSQ) only matches stops up to its `target`.

`arrivalTimeMessage` is usually `"N min"` but can be `"Delayed"` (seen live at NEW ToNY, with a
normal `secondsToArrival`). `TrainArrival` keeps it as-is; the UI should show it rather than
assume a minute count.

### Service alerts

`GET https://www.panynj.gov/bin/portauthority/everbridge/incidents?status=All&department=Path`

```text
status                "Success"
data[]
  incidentMessage
    subject
    preMessage          alert body text
    formVariableItems[] { variableName, val?: [String] }   e.g. "Lines" → ["HOB-WTC","HOB-33"], "Station" → ["HOB"]
  CreatedDate         ms since epoch, as a string
  ModifiedDate        ms since epoch, as a string
```

## Layout

```text
PATHStat.xcodeproj/          iOS app project (hand-written, objectVersion 77) + shared PATHStat scheme
PATHStat/                    SwiftUI app sources (file-system synchronized group)
Packages/PATHKit/
  Sources/PATHKit/           library: stations, lines, feed/alerts parsing, PATHClient
  Sources/path-live/         macOS debug CLI
  Tests/PATHKitTests/        Swift Testing suites + Resources/ridepath.json, alerts.json fixtures
```

Main `PATHKit` API: `PATHClient` (fetch and parse), `PATHSnapshot.departures(at:direction:toward:headsign:now:)`
→ `DepartureBoard` (sorted trains, `next`/`following`, `freshness`), `StationCatalog` (stations,
nearest station, lines and direction between stations), `ServiceAlert`, `PATHError`.

## Build, test, run

Requires Xcode 27 / Swift 6.4. No third-party dependencies.

```sh
swift test --package-path Packages/PATHKit                       # unit tests
PATH_LIVE=1 swift test --package-path Packages/PATHKit           # + live feed tests
swift run --package-path Packages/PATHKit path-live [STATION]    # live CLI, default GRV
xcodebuild -list -project PATHStat.xcodeproj
xcodebuild test -project PATHStat.xcodeproj -scheme PATHStat -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or open `PATHStat.xcodeproj` in Xcode and run the `PATHStat` scheme.

## Signing and roadmap notes

- `DEVELOPMENT_TEAM` is empty and signing is Automatic. Pick your team in Xcode to run on a
  device; a free personal team is enough for everything in the current scope.
- A paid Apple Developer account becomes useful later for APNs: push-to-start Live Activities
  and server-pushed Live Activity updates.
- App Groups (to share data between the app and a widget) will be evaluated in phase 3. They
  may not be needed, since the widget can fetch the public feed itself with `PATHKit`.
