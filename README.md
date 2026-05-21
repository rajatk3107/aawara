# Aawara — Personal Fitness Tracker

A privacy-first, offline fitness tracking app built with Flutter. All data is stored locally on device using SQLite — no accounts, no cloud sync, no data ever leaves your phone.

---

## Features

### Workout Tracker

**Home Screen**
- Time-of-day greeting with profile avatar
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
- **Rest timer** — auto-starts after each completed set; configurable default duration (30 s / 45 s / 1 m / 1.5 m / 2 m / 3 m / 4 m) via long-press on the rest bar; triple heavy haptic when time is up
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
- Monthly summary with highlights

**Workout History**
- Full log of every past session with duration, volume, and set counts
- Tap any entry to review the full set-by-set breakdown in read-only mode

**Achievements**
- Milestone badges unlocked automatically based on workout activity

---

### Nutrition Tracker

**Daily Log**
- Log food across four meals: Breakfast, Lunch, Dinner, Snack
- Daily macro summary ring (calories, protein, carbs, fat) with configurable goals
- Navigate between dates with a date strip

**Food Database**
- ~210 Indian foods sourced from IFCT 2017 (Indian Food Composition Tables, NIN) across 18 categories: Cereals, Pulses, Vegetables, Fruits, Dairy, Eggs, Poultry, Fish, Nuts, Indian Breads, South Indian, Rice Dishes, Dal & Curry, Snacks, Sweets, Beverages, Oils, and International/Gym foods
- Add custom foods with full macro breakdown

**Flexible Food Logging**
- **By count** — log by natural unit: eggs, bowls, rotis, glasses, pieces, scoops, etc. with smart step sizes
- **By grams** — enter exact weight; equivalent unit count shown below the field
- Switch between modes freely — values stay in sync

**Barcode Scanner**
- Tap the barcode icon in the food search sheet to scan a product barcode via camera
- Looks up nutritional data from Open Food Facts API (per 100 g)
- Checks if the food already exists in the local database by name — reuses it if found, creates it as a custom food if not
- Logs directly to the selected meal; no duplicates created

**Meal Presets**
- Bookmark any meal's logged items as a named preset (e.g. "My usual breakfast")
- One-tap logging: pick a preset → pick a meal → all items logged instantly
- Swipe-to-delete presets; accessible from the AppBar bookmark icon

**Water Tracker**
- Per-day water intake card with animated dot grid (one dot per glass)
- Configurable daily target (default 8 glasses / 2 L); tap the count to edit
- +/− buttons with light haptic feedback
- Progress bar + litre label

**Nutrition Goals**
- Set custom daily targets for calories, protein, carbs, and fat

---

### Wellness Log
- Daily entry for sleep hours, energy level (1–5), and soreness level (1–5)
- Optional notes per entry

---

### Notes
- Rich text editor (flutter_quill) for workout notes, thoughts, or anything else
- All notes stored locally in SQLite

---

### Settings & Data Management

**Export (Filtered Workout Export)**
- Export workout logs filtered by date range and optionally by a single exercise
- Formats: CSV (spreadsheet-friendly) or JSON (structured)
- Preview shows workout and set counts before exporting

**Full Backup**
- One tap exports everything: workouts, nutrition entries, custom foods, water logs, meal presets, body weight, wellness logs, achievements, exercise PRs, nutrition goals, day overrides, and quick-start templates
- Output is a single JSON file (schema_version: 3)

**Restore from Backup**
- Import any Aawara JSON export — full backups or legacy workout-only exports
- Safe merge: existing entries are never overwritten; duplicates are skipped
- Result card shows per-type import counts (workouts, nutrition entries, custom foods, water logs, etc.)

**Profile & Notifications**
- Profile photo and name (set during onboarding, editable in settings)
- Configurable workout reminder notifications

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3 / Dart 3 |
| Local database | sqflite (SQLite) |
| Charts | fl_chart |
| Rich text | flutter_quill |
| Image handling | image_picker + image_cropper |
| Barcode scanning | mobile_scanner |
| HTTP / Food API | http (Open Food Facts) |
| Data sharing | share_plus |
| File import | file_picker |
| Preferences | shared_preferences |
| ID generation | uuid |

**Theme**: Material 3, dark — `#0D0D1A` background, `#FFD700` gold accents, `#1A1A2E` card surfaces.

---

## Project Structure

```
lib/
├── main.dart                          # App entry, theme config
├── main_screen.dart                   # Bottom nav shell
├── splash_screen.dart
├── onboarding_screen.dart
├── home_screen.dart
├── settings_screen.dart
├── privacy_policy_screen.dart
├── services/
│   └── notification_service.dart
├── notes/
│   ├── note_model.dart
│   ├── notes_database.dart
│   ├── notes_list_screen.dart
│   └── note_editor_screen.dart
├── nutrition/
│   ├── models/
│   │   └── nutrition_models.dart      # Food, NutritionEntry, WaterLog, MealPreset, …
│   ├── screens/
│   │   ├── nutrition_screen.dart      # Daily log, macro ring, meal sections
│   │   ├── nutrition_goals_screen.dart
│   │   ├── meal_presets_screen.dart
│   │   ├── barcode_scanner_screen.dart
│   │   └── add_custom_food_screen.dart
│   └── widgets/
│       ├── add_food_sheet.dart        # Food search, count/gram toggle, barcode
│       └── water_tracker_card.dart
└── workout/
    ├── database/
    │   └── workout_database.dart      # SQLite singleton, all migrations
    ├── models/
    │   ├── exercise.dart              # Exercise, CardioType enum
    │   ├── workout_log.dart           # WorkoutLog, ExerciseLog, SetLog
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
    │   ├── monthly_summary_screen.dart
    │   ├── achievements_screen.dart
    │   ├── export_screen.dart
    │   └── import_screen.dart
    └── widgets/
        ├── exercise_tile.dart
        ├── muscle_group_filter.dart
        ├── set_log_tile.dart
        └── empty_state_widget.dart
```

---

## Database

Single SQLite file (`workout.db`) managed by a singleton `WorkoutDatabase`. All migrations are strictly additive — existing user data is never dropped or modified.

| Table | Purpose |
|---|---|
| `exercises` | Exercise library (seeded + custom, `is_custom` flag) |
| `workout_logs` | One row per workout session |
| `exercise_logs` | Exercises within a session |
| `set_logs` | Individual sets (weight, reps, cardio fields, completion) |
| `workout_plan_days` | Named plan days |
| `plan_day_exercises` | Exercises linked to a plan day |
| `day_overrides` | Per-date exercise list overrides |
| `quick_start_templates` | Saved PPL preset overrides |
| `body_weight_logs` | Daily body weight entries |
| `exercise_prs` | Personal records per exercise (best 1RM) |
| `wellness_logs` | Daily sleep, energy, and soreness entries |
| `achievements_unlocked` | Unlocked achievement IDs with timestamps |
| `foods` | Food library (~210 seeded Indian foods + custom, `is_custom` flag) |
| `nutrition_logs` | One row per date with nutrition entries |
| `nutrition_entries` | Individual food items per meal per date |
| `nutrition_goals` | User-configured daily macro targets |
| `meal_presets` | Saved meal combos |
| `meal_preset_items` | Foods within a meal preset |
| `water_logs` | Daily water intake (glasses drunk + target) |

Current schema version: **10**

---

## Getting Started

**Prerequisites**: Flutter 3.x, Android SDK (or Xcode for iOS)

```bash
cd aawara
flutter pub get
flutter run
```

**Run on Android emulator**:
```bash
flutter devices                        # find device id
flutter run -d <device-id>
```

**Build release APK (arm64)**:
```bash
flutter build apk --release --target-platform android-arm64
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## Data Safety

All data is stored locally. The only outbound network request is the optional Open Food Facts barcode lookup — no personal data is sent, and it is only triggered when the user scans a barcode. The SQLite database lives in the app's private storage directory. Use the Full Backup feature in Settings to export all your data as a JSON file at any time.

---

## Changelog

| Version | Changes |
|---|---|
| 1.0 | Initial release — workout logging, exercise library, PPL quick start, progress charts |
| 1.1 | Notes module, body weight log, workout plans, data export |
| 1.2 | Home screen redesign (week strip, stats, quick access grid), exercise progress tracking |
| 1.3 | Timer fix, accordion layout, drag reorder, delete set, persist checkmarks, manual entry, cardio logging, cardio exercise type, PPL template auto-save |
| 1.4 | Nutrition tracker — daily food log, macro ring, 210-item Indian food database (IFCT 2017), custom foods, nutrition goals, wellness log, achievements, monthly summary |
| 1.5 | Rest timer with configurable duration (long-press) + triple haptic; water intake tracker with animated dot grid; meal presets (save & log combos in one tap) |
| 1.6 | Barcode scanner (Open Food Facts API, camera, deduplication); by-count / by-grams food logging toggle with natural unit labels |
| 1.7 | Full data backup & restore — exports all 15 user-data tables to a single JSON file; safe merge import with per-type result counts |
