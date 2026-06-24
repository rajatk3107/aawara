# Aawara — Feature Ideas Backlog

A running list of candidate features. Built on data the app **already collects**,
favouring additions that fit the privacy-first, offline ethos. Pick one and we'll
brainstorm it into a spec, then build it.

**Legend:** 🟢 small / quick win · 🟡 medium · 🔴 large
Effort is rough engineering size; impact is perceived user value.

---

## ⭐ Recommended next three

- [x] **Progress photos** — ✅ already shipped (timeline, add/crop/note, detail view, compare side-by-side, share). Backlog item was stale.
- [ ] **Progressive-overload hints** — high impact, uses sets you already store
- [ ] **Weekly review screen** — ties all the data together

---

## Quick wins (small, high value)

- [x] 🟢 **Progress photos** — ✅ already implemented in `progress_photos_screen.dart` (grid
  timeline, camera/gallery + crop + note, zoomable detail, compare-mode side-by-side, share).
  Reachable from the workout home nav and the Progress screen.
- [ ] 🟢 **Supplement refill reminders** — optional "X servings left" count that decrements
  on each "Taken" and warns when ~7 days remain. Natural extension of the new supplement feature.
- [ ] 🟢 **Water & weigh-in reminders** — scheduled nudges using existing notification infra
  and daily water / body-weight logs.
- [ ] 🟢 **Plate calculator** — given a target barbell weight, show the plates per side. Pure logic.
- [x] 🟢 **Standalone 1RM calculator** — ✅ shipped. Epley estimate from weight × reps + a
  rep/percentage table (2/3/5/8/10/12 reps). Reachable from home Quick Access and the Progress
  screen. `one_rep_max.dart` (unit-tested) + `one_rep_max_calculator_screen.dart`.

## Workout depth

- [ ] 🟡 **Progressive-overload hints** — "Last time: 80 kg × 8. Try 82.5 kg or 9 reps."
  A query over stored sets + a hint chip on the set row.
- [ ] 🟡 **RPE / RIR per set** — log effort/reps-in-reserve alongside weight and reps.
- [ ] 🟢 **Warmup-set flagging** — mark sets as warmups so they're excluded from volume/PR math.
- [ ] 🟡 **Supersets / circuits** — group exercises so they're logged and rested as a unit.
- [ ] 🟡 **Muscle-group volume balance** — "You've trained chest 3× and legs 0× this week."
  Surfaces neglected groups from existing logs.
- [ ] 🟢 **Per-exercise form notes / cues** — a free-text note pinned to an exercise.

## Nutrition

- [ ] 🟡 **Recipe / dish builder** — combine foods into a saved scalable dish (per-gram), log
  it as one item. Goes beyond the existing meal presets.
- [ ] 🟢 **Copy yesterday's meals** — one tap to repeat a previous day's food log.
- [ ] 🟡 **Weekly nutrition trends** — calories / protein over time charts (fl_chart already in use),
  mirroring what Progress does for strength.
- [ ] 🟢 **Fasting timer** — start/stop eating window with elapsed display.

## Insights & engagement

- [ ] 🔴 **Weekly review screen** — auto summary: workouts, volume, nutrition adherence,
  supplement streak, average sleep. Pulls entirely from existing data.
- [ ] 🔴 **Correlations** — sleep / energy (wellness log) vs workout performance. Differentiated
  and genuinely useful.
- [ ] 🔴 **Android home-screen widget** — glanceable steps / water / supplements due.

## Cautious / out-of-ethos

These conflict with the privacy-first, offline positioning. Only if we want to change that.

- [ ] 🔴 **Cloud sync / accounts** — would mean data leaving the device.
- [ ] 🔴 **GPS run tracking** — location + maps, heavy and online.

---

## How to use this file

Tell me which item to pick up. I'll run it through brainstorming → spec → plan → build.
Check the box here once it ships, and we'll keep the list current.
