# Surfacing Samsung Watch Data in the App — Design Spec

**Date:** 2026-06-26
**Status:** Draft — for review
**Builds on:** the Samsung Health pipeline shipped in 1.1.4 (native bridge → `sh_*`
tables). This spec is the "show it in the UI" sub-project.

## Goal

The app already pulls and stores watch data (98 workouts, 16 nights synced). Make
it **visible**:

1. When viewing a workout, show its linked watch metrics (already partly done).
2. Browse all watch workouts and open a rich detail (metrics + HR chart + route map).
3. Surface watch workouts in the existing Workout History.
4. Use Samsung's real sleep score + SpO₂ series in the Sleep screen.

## Decisions (from brainstorming)

- **Where:** *Both* — a dedicated **Watch Activity** screen AND watch entries
  merged into **Workout History**.
- **Detail depth:** *Full* — headline metrics + **HR-over-time chart** + **GPS
  route map**.
- **Historical linking:** *Yes*, safe date-match for past logged workouts, gym-type
  single-candidate only.
- **Linking nuance (explicit):** also link by **time overlap**; a watch session at
  a different time (e.g. an evening walk) must **not** attach to a logged gym
  workout — it stays a separate, standalone workout.
- **Sleep:** *Yes* — use Samsung's score + SpO₂ on Samsung devices, fall back to
  the computed score / Health Connect otherwise.

---

## 1. Linking rules (precise)

A watch `sh_exercise_sessions` row links to at most one `workout_logs` row.

**Primary — time overlap (already built, keep):**
- For a logged workout with `started_at` set, compute its window
  `[started_at, started_at + duration_seconds]`.
- Link the watch session whose `[start_iso, end_iso]` **overlaps** that window
  (`session.start ≤ workout.end AND session.end ≥ workout.start`). Pick the
  best/closest if several overlap.
- **No overlap ⇒ no link.** An evening walk never attaches to a morning gym log.

**Fallback — historical (no `started_at`):**
- Match on the **same calendar day** only when there is **exactly one gym-type**
  candidate that day. "Gym-type" = NOT walking/running/hiking and NOT
  `autoDetected` (these are the things you wouldn't hand-log as a gym session).
- If 0 or >1 gym-type candidates that day ⇒ leave unlinked (never guess).

**Unmatched watch sessions** remain standalone — shown in Watch Activity and
History on their own, never glued to a workout.

**Pure & tested:** the candidate-selection logic (overlap test, gym-type filter,
single-candidate rule) is extracted into a pure function and unit-tested with
fixtures (morning gym + evening walk → only gym links; two same-day gym sessions →
neither links via fallback; overlapping session → links).

**Migration/run:** `linkSamsungToWorkouts()` is extended with the fallback and run
after each sync. A one-time backfill pass covers existing history.

---

## 2. Watch Activity screen (new)

`lib/workout/screens/watch_activity_screen.dart`

- Entry point: a tile in the workout home **Quick Access** grid ("Watch Activity").
- A list of **all** `sh_exercise_sessions`, newest first, grouped by month.
- Each row: exercise-type icon + name, date/time, duration, calories, distance,
  mean HR. A small **"logged"** chip when linked to a gym workout.
- A type filter chip row (All / Walking / Running / Workout / …) so the long list
  of auto-detected walks is filterable.
- Tap → Watch workout detail (§3).
- Loads from the DB (`getSamsungExercises(...)`); a pull-to-refresh triggers
  `SamsungHealthSync.syncNow()`.

New DB reads: `getSamsungExercises({int limit, String? typeFilter})`,
`getSamsungExerciseByUid(uid)` returning the row + its samples + route.

---

## 3. Watch workout detail (new)

`lib/workout/screens/watch_workout_detail_screen.dart`

- **Header:** type + custom title, date/time range, big duration.
- **Metric grid:** calories, distance, pace (derived: duration/distance),
  HR avg/max/min, mean/max cadence, mean/max power, VO₂max, calorie-burn-rate,
  altitude gain/loss — only the metrics present for that workout.
- **HR-over-time chart:** custom-painted line (reuse `SleepLineChart`-style painter,
  generalized) from `sh_exercise_samples` (hr vs time). Hidden if no samples.
- **Route map:** for outdoor workouts with route points — a map with the GPS
  polyline. **New dependency: `flutter_map`** (OpenStreetMap tiles, no API key) +
  `latlong2`. Hidden if no route.
- If this session is linked to a gym workout, a button to open that workout.

Pure helpers (tested): pace formatting (`min/km`), duration/HR formatting,
sample→chart-point mapping.

---

## 4. Workout History merge

`lib/workout/screens/workout_history_screen.dart` (edit)

- Add a segmented filter at the top: **Logged · Watch · All** (default Logged, so
  current behavior is unchanged unless toggled).
- In "Watch"/"All", interleave `sh_exercise_sessions` as cards with a **watch badge**
  and type icon, sorted by date with the logged entries.
- Tap behavior: a **linked** watch card (or its gym log) opens the gym workout
  (which shows the FROM WATCH card); an **unlinked** watch card opens the Watch
  detail (§3).
- Keep the existing type/date filters working for logged entries.

---

## 5. Sleep screen → Samsung data

`lib/workout/screens/sleep_screen.dart` + `sleep_service.dart` (edit)

- On Samsung devices, for a given night prefer the Samsung `sh_sleep_sessions`
  row: use its **`score`** (Samsung's real sleep score) and its stages.
- Render the **SpO₂ chart** from the watch SpO₂ series (via
  `SamsungHealthService.readVitalSeries('BLOOD_OXYGEN', …)` cached into
  `sleep_sessions.spo2_series_json`), finally giving the chart Health Connect
  couldn't.
- Fallback: if no Samsung sleep for the night, keep the current computed
  score + Health-Connect data path unchanged.
- A small "Samsung" source label when Samsung data is in use, so it's clear which
  score is shown.

---

## Data / architecture notes

- All reads come from the local `sh_*` tables (offline, fast); sync refreshes them.
- New dependencies: `flutter_map`, `latlong2` (route map only). If you'd rather
  avoid a map dependency, §3's map degrades to "route available — N points" text
  and we drop the deps; everything else is unaffected.
- No changes to the native bridge are required for any of this (data already
  flows); this is all Dart/UI + DB reads.

## Build order

1. Linking rules (pure + tested) + backfill.
2. Watch Activity list + DB reads.
3. Watch workout detail (metrics + HR chart).
4. Route map (`flutter_map`).
5. Workout History merge + filter.
6. Sleep screen Samsung integration (score + SpO₂).

Each chunk: analyze + release build + on-device check, version bump + changelog
per project policy.

## Out of scope (for now)

- Editing/deleting watch data (read-only mirror of Samsung Health).
- Analytics/aggregations over the watch data (trends, weekly load) — a later
  sub-project; the stored `raw_json` keeps that option open.
- Surfacing the other ~20 Samsung data types (steps, body composition, energy
  score…) in the UI — still a follow-up.

## Testing

- **Unit:** linking candidate selection; pace/duration/HR formatting; sample→chart
  mapping.
- **On-device:** open Watch Activity → see 98 workouts; open one → metrics + HR
  chart (+ map for outdoor); log a gym workout overlapping a watch session → it
  links and shows FROM WATCH; confirm an evening walk stays separate; Sleep screen
  shows Samsung score + SpO₂.
