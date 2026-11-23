# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Basmanager is a local-only SwiftUI iPhone app that reads "Smart15V" Bluetooth rechargeable batteries (AA/AAA).

- `SmartBattery/`: the Xcode project (`SmartBattery.xcodeproj`, created with Xcode). Targets: `SmartBattery` (app), `SmartBatteryLiveActivityExtension` (Live Activity widget), `SmartBatteryTests`, and an empty `SmartBatteryUITests`. Folders are synchronized with targets, so a file added to a folder joins that folder's target.
- `docs/`: spec, ADR and plan for the settings slice (`docs/specs/settings.md`, `docs/adr/0001-settings-scope.md`, `docs/plans/settings.md`).
- `_context/handoff/`: the session handoff document.

## Commands

Create and change the project only with Xcode (Xcode MCP project, target, file and build-setting tools, or the Xcode app). Do not use XcodeGen or edit the project file by hand.

Build and test with Xcode MCP (`BuildProject`, `RunAllTests`, `RunSomeTests`). A test needs an unlocked device or a simulator claimed with sim-pilot as the run destination. The fallback is `eyebuild`, which keeps artifacts under `/Volumes/eyedisk/build/basman/`:

```sh
cd SmartBattery
TMPDIR=/Volumes/eyedisk/tmp eyebuild xcodebuild sim-build -- -project SmartBattery.xcodeproj -scheme SmartBattery \
  -destination "id=<UDID>" test [-only-testing:SmartBatteryTests/StorageSafetyTests]
eyebuild rm sim-build
```

Tests use Swift Testing. A test for a spec criterion carries the ID in its display name, for example `@Test("AC-3.1 …")`.

Use RemoteDebug to put a Debug build on the user's iPhone. Increase `CURRENT_PROJECT_VERSION` on both the app and the extension target (Xcode build settings) first, then publish:

```sh
'/Users/oozoofrog/Library/Application Support/RemoteDebug/agent/rd' build /Volumes/eyedisk/develop/apps/basman/SmartBattery SmartBattery
```

Xcode writes build output to `SmartBattery/Build/`. The `.gitignore` excludes it.

## Architecture

The app creates its objects in `SmartBattery/SmartBattery/App/SmartBatteryApp.swift` and injects them with `.environment`, together with the low-battery threshold (`LowBatteryThreshold`, stored in `UserDefaults`):

- **`BatteryStore`** (`@MainActor @Observable`) is the single source of truth. The app uses `BatteryStore.onDevice()`; `BatteryStore(fileURL: nil)` is an in-memory store for tests and previews. When a data file exists but cannot be read, the store sets `batteryLoadFailed` or `chargingLoadFailed`, refuses changes and never writes that file (ADR-0001).
  - `registered`: the user's batteries. It persists as JSON in Application Support.
  - `sightings`: the live advertisements, keyed by peripheral UUID.
  - `connections`, `chargeStarts`, and `now`: runtime state.
  - The store owns the time-based rules. A one-second `tick` makes a battery go offline after 35 s without an advertisement. A charge start stays highlighted for 60 s.
- **`BatteryCentral`** owns `CBCentralManager` and feeds the store. Its delegate callbacks are `nonisolated` and hop with `MainActor.assumeIsolated`; the manager runs on the main queue.
  - It scans for service `AF30` with duplicates allowed and accepts only the local name `Smart15V`.
  - For a battery with `keepConnected`, it connects to the Nordic UART service and writes `E1 05 00 02` once per second. It parses the `E2 44 …` notifications.
  - `probe(_:)` is a read-only GATT dump for diagnostics. It must never write to the battery.
- **`BatteryProtocol.swift`** holds the wire format (`BatteryReading`) and the voltage-to-percent tables (`CapacityTable`). Real advertisements from two batteries matched the decoder.

The peripheral UUID is the battery's identity. It is stable only on one iPhone, so registrations cannot move between devices. The battery exposes no readable serial, the company ID `0x05D6` is the same on every unit, and iOS cannot read the MAC address. Because of this, a cross-device sharing feature was built and then removed. Do not reintroduce it unless the user asks.

## Constraints

- Do not write to the `AE00`/`AE01` service. It is probably the JieLi chip's firmware/OTA channel. The only command known to be safe is `BatteryProtocol.pollCommand`.
- The app sends nothing off the device. It has no account or server.
- The size bit in the advertisement is not reliable for every unit. Users override AA/AAA per battery with `sizeOverride`.
- The display name is Basmanager. The bundle ID stays `com.oozoofrog.SmartBattery` so that existing installs keep their data.
- Swift 6 language mode, default actor isolation `nonisolated`, approachable concurrency off. The minimum iOS version is 17. The signing team is `HY47J4787Q` with automatic signing.
- The project's development region is `en`, but the UI is Korean only. `ko.lproj/InfoPlist.strings` in the app and the extension gives each bundle a Korean localization, so iOS shows system text ("편집", relative dates) in Korean. Do not remove these files.
- `ChargingActivityAttributes` exists twice, in `SmartBattery/Model/` and `SmartBatteryLiveActivity/`, because each target compiles its own copy. Keep both copies identical.
