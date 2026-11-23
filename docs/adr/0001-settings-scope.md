# ADR-0001: Settings scope, data-file failure and check motion

## Context

The owner uses Basmanager as a personal app for the owner's own batteries. The owner removed the manufacturer's manual link, support phone and cautions from Settings, because they belong in the manufacturer's product. Three independent design passes proposed settings from three angles: tuning, data ownership and transparency. They found a data-loss defect. When the battery file cannot be decoded, `BatteryStore.load()` starts with an empty list, and the next save overwrites the file. The same load filters the charge history by the empty list, so the next charging save overwrites the charging file too. A later two-lens review found more paths to the same loss. Any read error is treated as a missing file. A charging file that cannot be decoded is silently replaced. The main list invites the owner to delete devices whose members only look deleted.

## Decisions

| # | Decision | Status |
|---|---|---|
| 1 | Settings shows the version with the build number, a read-only "저장된 데이터" section and the low-battery threshold. | Approved (user, 2026-11-24) |
| 2 | One low-battery threshold applies to the whole app: battery row colors and symbols, and device-check results. | Approved (user, 2026-11-24) |
| 3 | Settings has no check wait time, offline interval or backup export. | Approved (user, 2026-11-24) |
| 4 | On a load failure of the battery file, the app keeps the files untouched, refuses changes and shows the error. It does not start a new list. | Approved (user, 2026-11-24) |
| 5 | The device check shows signal reception with motion. | Approved (user, 2026-11-24) |
| 6 | The threshold range is 10...40 % in steps of 5, with a default of 20 %. It is stored in `UserDefaults` under `lowPercentThreshold`. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 7 | The threshold reaches views through one SwiftUI environment value set at the app root. `BatteryLevel` and the check status take the threshold as a parameter. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 8 | The reception indicator uses SF Symbols effects: a variable-color wave while waiting, and a replace transition to the result symbol. The section header shows a small progress ring. The views read `accessibilityReduceMotion`; when it is on, repeating effects are inactive and the ring changes without animation. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 9 | Settings receives the device store as a parameter, because `BatteryGroupStore` is owned by the main list. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 10 | The charging file gets the same protection as decision 4: on a load failure it is not written, goal changes are refused, and the error is shown. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 11 | Only `CocoaError.fileReadNoSuchFile` means a missing file. Every other read or decode error is a load failure. Production treats an unavailable Application Support folder as a load failure. Tests and previews use an explicit in-memory store. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |
| 12 | During a battery-file load failure, the main list hides registration and shows device members as "불러오지 못함" with device actions unavailable, so the device file is not changed by mistake. | AI-proposed; Approved (user, 2026-11-24, batch "진행") |

## Rationale

- One threshold keeps the red rows and the "잔량 낮음" results in agreement. A per-device value would change the device file format for a need nobody reported.
- The lower bound of 10 % is above the table minimum of 5 %, so the threshold can always be crossed. The upper bound of 40 % keeps an orange band below 50 %.
- Decisions 10–12 apply the owner's decision 4 to every path that the review found. Each path would otherwise destroy data that the owner decided to keep.
- Keeping the files costs usability: the app becomes read-only until the cause is removed. The routes that exist are installing a build that can read the file and restoring the iPhone from a backup. Deleting the app also deletes the files, so the error text does not suggest it.
- Apple's documentation does not state that variable-color symbol effects stop under Reduce Motion, so the views check the setting themselves.

## Consequences

- `BatteryStore` gains load-failure states for the battery and charging files, and every write path checks them. Its initializer distinguishes a file store from an in-memory store.
- `BatteryLevel.symbol` and `BatteryLevel.color` take a threshold. All callers pass the environment value.
- `BatteryGroupCheck.lowPercent` is removed. The check status reads the threshold instead.
- The device footer counts progress against the check total, not against all members.
- A threshold change re-colors existing rows and re-labels a finished check result.
