# Sleep Tracking from Health Connect — Design

**Date:** 2026-06-25
**Status:** Approved (pending spec review)
**Platform focus:** Android / Health Connect (the app's `health` integration is Android-first)

## Goal

Today sleep is a single manually-entered `sleep_hours` value in the Wellness log.
Replace that with automatic sleep tracking pulled from **Health Connect**: a
dedicated Sleep screen (stages, timeline, vitals, score, 7-day trend) and an
in-app home card, modelled on Samsung Health. Manual entry remains as a fallback.

The app already has a working Health Connect pipeline (`health` ^13.1.4,
currently STEPS-only) in `step_tracking_service.dart` — this feature extends that
same configure/permission/read flow to sleep.

## Decisions (from brainstorming)

- **Data scope:** sleep sessions + stages (awake/light/deep/REM) **plus** heart
  rate, blood oxygen (SpO₂), and respiratory rate correlated to the sleep window.
- **Home widget:** an in-app card on the workout home screen (NOT a native
  Android launcher widget).
- **Sleep score:** our own transparent 0–100 score (Samsung's score is not in HC).
- **Manual entry:** prefer Health Connect; manual fallback when no HC session
  exists for a night. Auto-fill `wellness_logs.sleep_hours` from HC.
- **Backfill:** 30 nights on first run.

## Honest limitations

Health Connect (via the `health` package) does **not** expose Samsung's
proprietary **Sleep Score**, **snoring**, or **bedtime guidance** — these are
computed inside Samsung Health and are omitted. Stage data only appears for
nights recorded by a wearable that writes stages to Health Connect; phone-only
nights may yield a single session with no stage breakdown.

## Architecture

### 1. Data layer — `sleep_sessions` table (schema v21)

One row per night, keyed by **wake date** (`date`, UNIQUE):

| Column | Purpose |
|---|---|
| `date` | YYYY-MM-DD of the wake day (UNIQUE) |
| `start_iso`, `end_iso` | session bounds |
| `total_minutes` | end − start (time in bed) |
| `asleep_minutes` | total − awake (actual sleep) |
| `awake_minutes`, `light_minutes`, `deep_minutes`, `rem_minutes` | per-stage totals |
| `score` | our computed 0–100 score |
| `hr_avg`, `hr_min` | heart rate during the window |
| `spo2_avg`, `spo2_min` | blood oxygen during the window |
| `resp_avg` | respiratory rate during the window |
| `source` | `health_connect` or `manual` |
| `stages_json` | ordered timeline segments `[{stage,start,end}]` for the hypnogram |

Cached locally so the screen works offline and shows history. Migrations are
additive (existing pattern). New CRUD: `upsertSleepSession`, `getSleepSession(date)`,
`getSleepSessions(fromDate,toDate)`.

### 2. Service layer — `SleepService`

Mirrors `StepTrackingService`'s configure/permission helpers (reuse the same
`Health` instance pattern).

- Read types: `SLEEP_SESSION`, `SLEEP_ASLEEP`, `SLEEP_AWAKE`, `SLEEP_AWAKE_IN_BED`,
  `SLEEP_DEEP`, `SLEEP_LIGHT`, `SLEEP_REM`, `HEART_RATE`, `BLOOD_OXYGEN`,
  `RESPIRATORY_RATE` (all READ).
- `syncNight(DateTime date)`: fetch the sleep session(s) for the night, aggregate
  stages, correlate vitals records within `[start,end]` (avg + min), compute the
  score, upsert the row, and update `wellness_logs.sleep_hours` for that date
  (preserving energy/soreness if a row exists).
- `syncHistory({int days = 30})`: backfill loop; first-run trigger.
- `hasSleepPermission()` / `requestSleepPermission()`: HC grant flow.
- Triggers: on app resume and when the Sleep screen opens; 30-day backfill on
  first run (guarded by a `SharedPreferences` flag).

### 3. Pure, unit-tested helpers (`lib/workout/utils/sleep_metrics.dart`)

Isolated from the `health` plugin so they're testable:

- `int computeSleepScore({required int asleep, required int deep, required int rem, required int awake, required int total})`
  → 0–100. Formula (transparent, capped):
  - duration: `50 * min(asleep / 450, 1.0)`
  - deep: `20 * min((deep/asleep) / 0.18, 1.0)`
  - rem: `20 * min((rem/asleep) / 0.22, 1.0)`
  - efficiency: `10 * (asleep / total)`
  - sum, round, clamp 0–100. Guards against zero/empty inputs (returns 0).
- `SleepStageTotals aggregateStages(List<SleepStageSegment> segments)`
  → per-stage minutes + ordered normalized timeline. `SleepStageSegment` is a
  plain `{stage, start, end}` value type the service maps `HealthDataPoint`s into,
  keeping the parser plugin-free.

### 4. UI — `SleepScreen` (`lib/workout/screens/sleep_screen.dart`)

- **Header:** Sleep Score (our score), total sleep time, actual (asleep) time, with
  prev/next day navigation.
- **Hypnogram:** custom-painted stage timeline (Awake / REM / Light / Deep levels
  across the night) from `stages_json`.
- **Stage breakdown:** Awake/REM/Light/Deep rows — %, duration, horizontal bar
  (colors echo Samsung: pink awake, light-purple REM, purple light, deep-purple deep).
- **Vitals during sleep:** HR avg, SpO₂ avg, respiratory avg cards (hidden if absent).
- **7-day trend:** simple duration bars.
- **Manual fallback:** when no HC session exists for the night, an "Add manually"
  action that writes hours (`source = manual`, also updates wellness).
- **Permission state:** if HC access not granted, a prompt with a "Connect"
  button invoking `requestSleepPermission()`.

### 5. UI — home `SleepCard` (`lib/workout/widgets/sleep_card.dart`)

On the workout home screen near `StepCounterCard`: last night's score + total
duration + a mini stacked stage bar. Tap → `SleepScreen`. Also add a Sleep tile to
the Quick Access grid for discoverability. Loads from `sleep_sessions` (no blocking
network); a background `syncNight` refresh updates it.

### 6. Manifest

Add health read permissions:
`android.permission.health.READ_SLEEP`, `READ_HEART_RATE`,
`READ_OXYGEN_SATURATION`, `READ_RESPIRATORY_RATE`.

## Data flow

```
app resume / Sleep screen open
   └─ SleepService.syncNight(today)
        ├─ health.getHealthDataFromTypes(sleep + vitals, window)
        ├─ aggregateStages(...)            → stage minutes + timeline
        ├─ correlate vitals in [start,end] → hr/spo2/resp
        ├─ computeSleepScore(...)          → 0–100
        ├─ upsertSleepSession(row)
        └─ update wellness_logs.sleep_hours
   └─ SleepCard / SleepScreen read sleep_sessions from DB
```

## Out of scope (YAGNI)

- Native Android home-screen widget.
- Samsung-only metrics (sleep score replication, snoring, bedtime guidance).
- Writing sleep back to Health Connect (read-only).
- iOS HealthKit sleep (project is Android-focused; the screen degrades to manual
  on iOS).
- Editing/splitting individual stage segments.

## Testing

- **Unit:** `computeSleepScore` (normal, zero-input, capping) and `aggregateStages`
  (stage totals, ordering, gaps).
- **Manual on-device:** grant HC sleep permission, sync a real night, verify the
  hypnogram, stage breakdown, vitals, and score render; confirm the home card and
  the wellness sleep hours update; verify manual fallback on a night with no HC data.
