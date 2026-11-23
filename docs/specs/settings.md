# Spec: Settings for a personal app, and device-check reception motion
Status: Approved (user, 2026-11-24). Scope from ADR-0001 decisions 1–5; acceptance criteria AI-proposed and approved as a batch ("진행").

## Goal

Basmanager is a personal app for the owner's own batteries and devices. The Settings screen shows only what the owner needs on this iPhone: the installed build, what the app stores, and one tuning value. The app MUST NOT lose the owner's data when a data file cannot be read. A device check shows the reception of each battery's signal with motion.

## Terms

- **Low-battery threshold**: the estimated percent below which a battery counts as low. One value for the whole app (ADR-0001, decision 2).
- **Battery file**: `registered-batteries.json` in Application Support.
- **Charging file**: `registered-batteries.charging.json` in Application Support.
- **Device file**: `battery-groups.json` in Application Support.
- **Missing file**: reading the file fails with `CocoaError.fileReadNoSuchFile`.
- **Load failure**: the file is not missing, but reading or decoding it fails. Production also reports a load failure when the Application Support folder is unavailable.
- **In-memory store**: a store created for tests or previews without a file. It never reports a load failure and never writes.
- **Check total**: the members of a device whose registration exists when the check starts. The check waits for these members only.

## Acceptance criteria

| ID | Keyword | Criterion | Verification |
|---|---|---|---|
| AC-1.1 | MUST | When Settings opens, the "버전" row shows the marketing version and the build number as `<version> (<build>)`, for example `1.0.0 (10)`. A missing key shows `–` in its place. | live: Settings on device |
| AC-2.1 | MUST | When Settings opens with no load failure, a "저장된 데이터" section shows the number of registered batteries, the number of devices and the number of charge history entries. | live: Settings on device |
| AC-2.2 | MUST | When no file failed to load, the "저장된 데이터" footer states that the data is kept only on this iPhone and is not sent anywhere, that an iPhone backup can include it, and that another iPhone needs the batteries registered again. | live: Settings on device |
| AC-2.3 | MUST | When the charging file failed to save, Settings shows "충전 기록을 저장하지 못했어요" and a "다시 저장" button. The button retries the save. | live: register one battery; while the app runs, replace the charging file with a folder, change the charge goal, open Settings and see the row; remove the folder, tap 다시 저장, see the row disappear |
| AC-3.1 | MUST | On a load failure of the battery file, the store reports it and MUST NOT write the battery file. | loadFailureNeverOverwritesBatteryFile |
| AC-3.2 | MUST | On a load failure of the battery file, the store MUST NOT write the charging file. | loadFailureNeverOverwritesChargingFile |
| AC-3.3 | MUST | On a load failure of the battery file, register, update, delete and move change nothing, and register returns false. | loadFailureRefusesChanges |
| AC-3.4 | MUST | On a load failure of the battery file, the main list shows "건전지 목록을 불러오지 못했어요" with the next action: install the latest build or restore the iPhone from a backup. | live: corrupt battery file on simulator |
| AC-3.5 | MUST | When the battery file is missing, the store starts with an empty list and reports no load failure. | missingBatteryFileIsNotAFailure |
| AC-3.6 | MUST | When the battery file exists but cannot be read (for example, a folder at its path), the store reports a load failure. | unreadableBatteryFileIsAFailure |
| AC-3.7 | MUST | On a load failure of the battery file, the main list hides the unregistered section, the empty state and every register action. | live: corrupt battery file on simulator with a battery in range |
| AC-3.8 | MUST | On a load failure of the battery file, device sections show their members as "불러오지 못함", not "등록 삭제됨", and the device edit, delete, replacement and reorder actions are unavailable. | live: corrupt battery file on simulator with a device saved |
| AC-3.9 | MUST | On a load failure of the charging file, the store keeps the default goal and an empty history in memory, MUST NOT write the charging file, and refuses goal changes. | chargingLoadFailureNeverOverwritesChargingFile |
| AC-3.10 | MUST | On a load failure of the charging file, Settings and the charging screen show "충전 기록을 불러오지 못했어요" with the same next action as AC-3.4. | live: corrupt charging file on simulator |
| AC-3.11 | MUST | During a load failure of any file, "저장된 데이터" shows the failure row in place of the count from that file, and its footer shows the next action from AC-3.4. Counts from files that loaded stay visible. | live: corrupt each file in turn on simulator |
| AC-3.12 | MUST | An in-memory store accepts changes, never writes and never reports a load failure. | inMemoryStoreAcceptsChanges |
| AC-4.1 | MUST | Settings has a "잔량 낮음 기준" control from 10 % to 40 % in steps of 5 %. The default is 20 %. The value persists across app launches. | lowThresholdPersistsAndDefaults |
| AC-4.2 | MUST | A stored threshold outside 10...40 or not a multiple of 5 is read as the nearest allowed value. | lowThresholdClampsStoredValue |
| AC-4.3 | MUST | For a battery that is not charging, an estimated percent below the threshold uses red and `battery.25percent`, and a percent from the threshold to below 50 % uses orange and `battery.50percent`. A charging battery keeps `battery.100percent.bolt` and uses the threshold only for its color. | batteryLevelUsesThreshold |
| AC-4.4 | MUST | A device check reports "잔량 낮음" for a member exactly when its sampled percent is below the threshold. | checkStatusUsesThreshold |
| AC-4.5 | MUST | A threshold change takes effect in the list and in a finished check result without relaunching the app. | live: change threshold, return to list |
| AC-5.1 | MUST | While a device check waits, each member row without an answer shows an animated reception indicator next to "점검: 수신 대기 중". | live: start a check on device |
| AC-5.2 | MUST | When a member answers, its indicator changes to the result with a transition animation. The section shows received/check-total progress that animates as it grows, and a finished check where every member in the check total answered shows full progress. Members whose registration was deleted are listed as excluded, for example "삭제된 건전지 1개 제외". | progressUsesCheckTotal; live: start a check on device |
| AC-5.3 | MUST | With Reduce Motion on, no indicator repeats or moves, and the progress changes without animation. The status text and progress numbers still change. | live: Reduce Motion on simulator or device |
| AC-5.4 | MUST NOT | Rows MUST NOT change order during or after a check. | live: start a check on device |

## Out of scope

- Check wait time, offline interval and backup export. The owner decided not to add them (ADR-0001, decision 3).
- Per-device thresholds.
- An in-app way to discard an unreadable file and start again. ADR-0001 decision 4 forbids it. It needs a separate owner decision.
- Manufacturer manual, support phone and product cautions.
