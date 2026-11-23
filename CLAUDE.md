# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Basmanager is a local-only SwiftUI iPhone app that reads "Smart15V" Bluetooth rechargeable batteries (AA/AAA).

- `ios/`: the app. The XcodeGen spec is `ios/project.yml`. The generated `SmartBattery.xcodeproj` is disposable.
- `_context/handoff/`: the session handoff document.

## Commands

Run these from `ios/`. Regenerate the project after you add or remove files, or after you edit `project.yml`:

```sh
xcodegen generate
```

Build and test with Xcode MCP when it is available. The fallback is `eyebuild`, which keeps artifacts under `/Volumes/eyedisk/build/basman/`:

```sh
TMPDIR=/Volumes/eyedisk/tmp eyebuild xcodebuild sim-build -- -project SmartBattery.xcodeproj -scheme SmartBattery \
  -destination 'generic/platform=iOS Simulator' build-for-testing
# Tests need a booted simulator. Claim one with sim-pilot first.
TMPDIR=/Volumes/eyedisk/tmp eyebuild xcodebuild sim-build -- -project SmartBattery.xcodeproj -scheme SmartBattery \
  -destination "id=<UDID>" test-without-building [-only-testing:SmartBatteryTests/BatteryProtocolTests/decodesAdvertisement]
eyebuild rm sim-build
```

Tests use Swift Testing (`@Test`) and live in `SmartBatteryTests/BatteryProtocolTests.swift`.

Use RemoteDebug to put a Debug build on the user's iPhone. Increase `CURRENT_PROJECT_VERSION` in `project.yml` first, then publish:

```sh
'/Users/oozoofrog/Library/Application Support/RemoteDebug/agent/rd' build /Volumes/eyedisk/develop/apps/basman/ios SmartBattery
```

The RemoteDebug build writes `ios/Build/`. The `.gitignore` excludes it.

## Architecture

The app creates two objects and injects both with `.environment` (`App/SmartBatteryApp.swift`):

- **`BatteryStore`** (`@MainActor @Observable`) is the single source of truth.
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
- Swift 6 language mode with strict concurrency. The minimum iOS version is 17. The signing team is `HY47J4787Q` with automatic signing.
