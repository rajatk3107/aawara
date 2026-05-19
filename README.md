# Aawara — Personal Fitness Tracker

A privacy-first, offline fitness tracking app built with Flutter. All data is stored locally on device using SQLite — no accounts, no cloud sync, no data ever leaves your phone.

---

## Features

### Workout Tracker (Core)

**Home Screen**
- Time-of-day greeting with avatar
- Interactive 7-day week strip — tap any day to preview that day's planned workout
- Today's workout card showing planned exercises with a one-tap Start button
- Stats strip: current streak, workouts this week, total weight lifted, monthly count, and today's volume
- Quick access 2×2 grid (Quick Start, Exercise Library, Progress, History)

**Quick Start**
- PPL (Push/Pull/Legs) presets: Push A/B, Pull A/B, Legs A/B — each with 6–7 curated exercises
- Muscle group shortcuts (Chest, Back, Shoulders, Arms, Legs, Core, Full Body)
- Full exercise editor before starting: reorder (drag), remove (swipe), add from library
- Edits auto-save back to the preset template — next launch remembers your order

**Workout Logging**
- Elapsed timer during active workouts; shows stored duration on completed workouts
- Accordion layout — tap any exercise to expand its set list in-place
- Drag handles to reorder exercises during an active session
- Set row controls: stepper (+/−) for weight and reps, tap the value to type directly
- Swipe left on a set row to delete it; add as many sets as needed
- Checkmarks per set — persisted to the database, restored when viewing a completed workout
- Rest timer auto-starts (90 s) after each completed set with haptic feedback
- Cardio logging per machine type:
  - **Treadmill**: duration, speed (km/h), incline (%)
  - **Cross Trainer / Cycling**: duration, resistance level
  - **Rowing Machine**: duration, distance (km)
  - **Stair Climber**: duration, speed (steps/min)
  - **Other cardio**: duration, distance

**Exercise Library**
- 50+ pre-seeded exercises across all muscle groups
- Search by name, filter by muscle group
- Add custom exercises: choose Strength or Cardio type, muscle group / machine type, equipment
- Edit or delete custom exercises
- Swipe-to-delete with confirmation

**Workout Plans**
- Create named plan days linked to specific exercises
- View and manage multi-day training plans

**Progress**
- Strength tab: total volume over time, exercise-specific progress charts (fl_chart), personal record tracking
- Body weight log with trend chart
- Exercise tracker: per-exercise history of best set, total volume, and one-rep-max estimate
- Data export: download all workout data as JSON or CSV

**Workout History**
- Full log of every past session with duration, volume, and set counts
- Tap any entry to review the full set-by-set breakdown in read-only mode

### Notes
- Rich text editor (flutter_quill) for workout notes, thoughts, or meal plans
- All notes stored locally in SQLite

### Onboarding
- First-launch photo selection and name entry
- Splash screen

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3 / Dart 3 |
| Local database | sqflite (SQLite) |
| Charts | fl_chart |
| Rich text | flutter_quill |
| Image handling | image_picker + image_cropper |
| Data sharing | share_plus |
| ID generation | uuid |

**Theme**: Material 3, dark — `#0D0D1A` background, `#FFD700` gold accents, `#1A1A2E` card surfaces.

---

## Project Structure

```
lib/
├── main.dart                      # App entry, theme config
├── main_screen.dart               # Bottom nav shell
├── splash_screen.dart
├── onboarding_screen.dart
├── home_screen.dart
├── notes/
│   ├── note_model.dart
│   ├── notes_database.dart
│   ├── notes_list_screen.dart
│   └── note_editor_screen.dart
└── workout/
    ├── database/
    │   └── workout_database.dart  # SQLite singleton, migrations
    ├── models/
    │   ├── exercise.dart          # Exercise, CardioType enum
    │   ├── workout_log.dart       # WorkoutLog, ExerciseLog, SetLog
    │   └── workout_plan_day.dart
    ├── screens/
    │   ├── workout_home_screen.dart
    │   ├── quick_start_screen.dart
    │   ├── workout_logging_screen.dart
    │   ├── workout_complete_screen.dart
    │   ├── workout_history_screen.dart
    │   ├── workout_plan_screen.dart
    │   ├── exercise_library_screen.dart
    │   ├── progress_screen.dart
    │   ├── exercise_progress_screen.dart
    │   ├── exercise_progress_detail_screen.dart
    │   └── export_screen.dart
    └── widgets/
        ├── exercise_tile.dart
        ├── muscle_group_filter.dart
        └── set_log_tile.dart
```

---

## Database

Single SQLite file (`workout.db`) managed by a singleton `WorkoutDatabase`. Migrations are additive (`ALTER TABLE ADD COLUMN`) — existing data is never dropped or modified.

| Table | Purpose |
|---|---|
| `exercises` | Exercise library (seeded + custom) |
| `workout_logs` | One row per workout session |
| `exercise_logs` | Exercises within a session |
| `set_logs` | Individual sets (weight, reps, cardio fields, completion) |
| `workout_plan_days` | Named plan days |
| `plan_day_exercises` | Exercises linked to a plan day |
| `quick_start_templates` | Saved PPL preset overrides |
| `body_weight_logs` | Daily body weight entries |

Current schema version: **5**

---

## Getting Started

**Prerequisites**: Flutter 3.x, Android SDK (or Xcode for iOS)

```bash
cd aawara
flutter pub get
flutter run
```

**Build release APK (arm64)**:
```bash
flutter build apk --release --target-platform android-arm64
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Data Safety

All data is local. No network requests are made. The SQLite database lives in the app's private storage directory on the device. Use the Export screen to back up your data as JSON or CSV at any time.

---

## Changelog

| Version | Changes |
|---|---|
| 1.0 | Initial release — workout logging, exercise library, PPL quick start, progress charts |
| 1.1 | Notes module, body weight log, workout plans, data export |
| 1.2 | Home screen redesign (week strip, stats, quick access grid), exercise progress tracking |
| 1.3 | Timer fix, accordion layout, drag reorder, delete set, persist checkmarks, manual entry, cardio logging, cardio exercise type, PPL template auto-save |
