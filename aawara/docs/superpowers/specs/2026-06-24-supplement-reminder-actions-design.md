# Interactive Supplement Reminders — Design

**Date:** 2026-06-24
**Status:** Approved
**Scope:** Supplement reminders only (workout reminders unchanged)

## Goal

Today, adding a supplement schedules a daily reminder that fires at the chosen
time (`NotificationService.scheduleDailyReminder`, notification ID `1000 + supplementId`).
The body says "tap to mark taken," but tapping does nothing — there is no tap
handler, no action buttons, no snooze.

Make the reminder interactive: let the user **mark the supplement taken** or
**snooze** it straight from the notification drawer, without needing to open and
navigate the app.

## Decisions (from brainstorming)

- **Alert style:** heads-up notification with action buttons. NOT full-screen
  intent (rejected for OEM flakiness and the special Android 14+ permission).
- **Actions:** two buttons — `✓ Taken` and `💤 Snooze`.
- **Snooze UX:** `Snooze` opens the app to a quick picker (15m / 30m / 1h). Two
  buttons keep the drawer clean while still offering a duration choice.
- **Scope:** supplements only. Workout reminders untouched.

## Behavior

When a supplement reminder fires:

```
┌────────────────────────────────┐
│ 💊 Creatine                     │
│ 5 g · time to take it          │
│ [ ✓ Taken ]   [ 💤 Snooze ]     │
└────────────────────────────────┘
```

- **✓ Taken** — silently writes today's `supplement_logs` row and dismisses the
  notification. Does NOT open the app.
- **💤 Snooze** — opens the app to a snooze picker (15m / 30m / 1h). The chosen
  delay schedules a one-shot copy of the reminder; the original is dismissed.
- **Tap body** — opens the app on the Supplements screen.

## Architecture

### 1. NotificationService (`lib/services/notification_service.dart`)

- New dedicated channel `supplement_reminders` (importance high, vibration).
- `scheduleDailyReminder` gains two `AndroidNotificationAction`s:
  - `mark_taken` — `showsUserInterface: false`, `cancelNotification: true`
    (silent background action, no app launch).
  - `snooze` — `showsUserInterface: true` (launches the app).
- **Payload** encodes what to act on. Format: `supp|<id>|<name>|<dose>`.
  The action date is "today" computed in the handler at action time (the day the
  user taps), which is correct because the reminder fires on the target day.
- New `scheduleSnooze({required int supplementId, required String name, String? dose, required int minutes})`
  — one-shot `zonedSchedule` at `now + minutes` with identical content + actions.
  Reuses notification ID `1000 + supplementId` so a new snooze replaces any prior
  pending snooze for that supplement.
- `initialize()` registers both response callbacks:
  - `onDidReceiveNotificationResponse` — foreground.
  - `onDidReceiveBackgroundNotificationResponse` — top-level
    `@pragma('vm:entry-point')` function for background/killed app.

### 2. Response handling

- **Background isolate** (`mark_taken`, app killed/backgrounded): the top-level
  handler calls `WidgetsFlutterBinding.ensureInitialized()` +
  `DartPluginRegistrant.ensureInitialized()`, parses the payload, then
  `WorkoutDatabase.instance.markSupplementTaken(id, today)`. Safe because
  `supplement_logs` has `PRIMARY KEY (supplement_id, date)` and the insert uses
  `ConflictAlgorithm.replace` — fully idempotent even if also handled in
  foreground.
- **Foreground** (`mark_taken`, app open): same DB write, then bump a global
  refresh signal so an open Supplements screen reloads live, then
  `cancelById(1000 + id)`.
- **Snooze** (always launches app): foreground handler — or
  `getNotificationAppLaunchDetails()` at cold start — sets a pending-action
  `ValueNotifier<PendingSupplementAction?>`. A listener at the app root shows the
  snooze picker sheet for that supplement.

### 3. Snooze picker (`_SnoozePickerSheet`)

A dark-themed modal bottom sheet matching the existing `_SupplementEditorSheet`
styling, with three chips: **15 min**, **30 min**, **1 hour**. On selection →
`NotificationService.instance.scheduleSnooze(...)`, dismiss the original
notification, show a confirmation SnackBar.

### 4. Refresh signal (`lib/services/supplement_events.dart`)

A lightweight global `ValueNotifier<int> supplementsChanged`, bumped whenever a
log is written from a notification action (foreground path). The Supplements
screen adds a listener in `initState` that reloads `_takenToday` /adherence on
change, and removes it in `dispose`.

### 5. main.dart

- Provide a `GlobalKey<NavigatorState>` to `MaterialApp` (if not already present)
  so the root can present the snooze sheet.
- On startup, after the first frame, check `getNotificationAppLaunchDetails()`
  for a pending `snooze` action and route it.

### 6. AndroidManifest

- Verify `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver` is
  registered. Add it next to the existing
  `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` if the
  plugin does not declare it in its own merged manifest — without it, action-button
  taps are not delivered when the app is backgrounded/killed.
- No new permissions needed (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
  `RECEIVE_BOOT_COMPLETED` already present).

## Data flow

```
fire time ── notification (Taken / Snooze) ──┐
                                             │
   tap "Taken" (bg)  → background isolate → WorkoutDatabase.markSupplementTaken → dismiss
   tap "Taken" (fg)  → foreground handler → markSupplementTaken → supplementsChanged++ → dismiss
   tap "Snooze"      → launch app → pending action → _SnoozePickerSheet
                          → pick 15/30/60m → scheduleSnooze → dismiss original
   tap body          → launch app → Supplements screen
```

## Payload helper (pure, unit-tested)

`encodeSupplementPayload(id, name, dose)` → `"supp|id|name|dose"`
`decodeSupplementPayload(String)` → `{id, name, dose}` or null.
Names/doses are sanitized of the `|` delimiter before encoding.

## Out of scope (YAGNI)

- Full-screen alarm intent.
- "Undo" action on the notification (in-app tap already toggles).
- Custom iOS action background handling — iOS still shows the notification; the
  custom DB-write-on-action path is Android-focused (the project's target).
- Applying actions to workout reminders (possible follow-up).

## Testing

- **Unit:** `encode/decodeSupplementPayload` round-trip, including names
  containing `|` and empty dose.
- **Manual:**
  1. Add a supplement timed ~1 min out, background the app.
  2. Tap **✓ Taken** → on resume, the row shows taken and adherence increments;
     notification is gone.
  3. Fire again, tap **💤 Snooze → 15m** → original dismissed, a new reminder is
     pending ~15 min out.
  4. With the app open on the Supplements screen, tap **✓ Taken** from the
     drawer → the row updates live without manual refresh.
