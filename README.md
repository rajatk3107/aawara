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
- **Step counter card** — live step count, progress bar, edit button, and refresh
- **Protein / calorie pill** — tappable, navigates directly to the Nutrition screen
- **Quick access grid** — Progress, Exercises, Quick Start, History, and **Body Measurements**
- **Date-aware data** — when you tap a different day on the week strip, **every** widget on the home screen updates to reflect that date: workout logs, protein/calorie pill, water intake, wellness card, body weight (as-of-date lookup), and step count

**Quick Start**
- PPL (Push/Pull/Legs) presets: Push A/B, Pull A/B, Legs A/B — each with 6–7 curated exercises
- Muscle group shortcuts (Chest, Back, Shoulders, Arms, Legs, Core, Full Body)
- Full exercise editor before starting: reorder (drag), remove (swipe), add from library
- Edits auto-save back to the preset template — next launch remembers your order

**Workout Logging**
- Elapsed timer during active workouts; shows stored duration on completed workouts
- **RUNNING / PAUSED badge** next to the timer with colored chip (green when running, orange when paused) — the timer also turns orange when paused, white when running
- **Prominent Pause / Resume button** at the top-right of the workout screen with text labels and matching colors; manual control only — the timer never auto-pauses when you navigate to other screens
- **Timer survives navigation** — uses a wall-clock anchor persisted to SharedPreferences, so elapsed time stays accurate regardless of how long you spend on other tabs/screens
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

**Dynamic Meal System**
- Start with 5 meals (Meal 1–5); create additional meals (Meal 6, 7, …) at any time
- **Custom meal names** — long-press any meal header or use the ⋮ menu → Rename meal. Names persist across app restarts
- **Delete entire meal** — ⋮ menu → Delete meal removes the slot and all its food log entries permanently; at least one meal must remain
- Previous fixed meals (Breakfast/Lunch/Dinner/Snack) automatically migrated to Meal 1–4

**Meal Picker**
- Tapping **Add Food** shows a meal picker sheet listing all active meals
- "Create new meal" option at the bottom — enter a name and the new meal slot is created instantly; food search opens into it immediately

**Editable Food Entries**
- Every logged food entry has a **⋮ overflow menu** with:
  - **Edit quantity** — opens a quantity picker (by count or by grams) with live macro preview; save updates the entry and all daily totals
  - **Move to meal** — reassign an entry to any other meal without re-logging
  - **Delete** — confirmation dialog; removes the entry and recalculates all totals
- **Delete all items** — ⋮ on the meal header removes all entries in that meal for the current date

**Food Database**
- ~220 Indian and international foods sourced from IFCT 2017 and USDA FoodData Central across 19 categories
- Extended nutritional data for all foods: **sugar, sodium, saturated fat, trans fat, cholesterol** in addition to the standard macros
- Supplements and branded foods: BeastLife Creatine Unflavoured, BeastLife Isorich Whey Protein Isolate, NATURALTEIN Natural Whey Protein Isolate Chocolate, True Elements Steel Cut Oats, BeastLife Pre-Workout Orange Flavour, BeastLife Multivitamin Tablets, NATURALTEIN Omega-3 Fish Oil 1250 mg Softgel, Indian Cow Milk without Malai, Indian Buffalo Milk without Malai
- Corrected nut values to USDA: Almonds, Cashews, Walnuts, Pistachios

**Custom Foods — Create, Edit, Delete**
- "Create custom" entry point in the food search sheet; enter name, serving size, unit, and macros **per serving** (no need to convert to per-100 g — the app does that internally so calculations stay accurate at any serving size)
- "Custom" badge displayed next to user-created foods in the search results
- **⋮ menu on every custom food row** — Edit (re-opens the form pre-filled with current values) or Delete (also removes any logged entries that referenced it)
- Seeded foods are read-only; the ⋮ menu only appears on `is_custom = 1` rows

**Correct Nutrition Scaling**
- All nutritional values stored per 100 g; correctly scaled by `quantity × servingSize / 100` when displayed and summed — accurate for any serving size (30 g almonds, 33 g scoop of whey, 7 g pre-workout, etc.)

**Flexible Food Logging**
- **By count** — log by natural unit: eggs, bowls, rotis, glasses, pieces, scoops, etc. with smart step sizes
- **By grams** — enter exact weight including decimals (e.g. 37.5 g); equivalent unit count shown below the field
- Switch between modes freely — values stay in sync
- **Decimal quantities** — 0.25, 0.5, 1.5 bowls, 2.75 scoops, etc. supported in both modes

**TDEE Calculator with Custom Overrides**
- Mifflin-St Jeor BMR → TDEE with activity multiplier and goal offset
- **Tap any result value** (calories, protein, carbs, fat) to override with a custom number
- Custom values highlighted with brighter border; individual or bulk reset to calculated
- Overrides persist across app restarts via SharedPreferences
- "Apply as my goals" saves the final values (custom override wins) to the nutrition goals

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

### Step Tracking

**Android**
- Persistent foreground service with hardware pedometer
- Survives app kill; midnight baseline reset with device-reboot handling
- Foreground notification shows live step count and goal progress
- Health Connect integration — Samsung Watch and other wearable data merged automatically

**iOS**
- Reads from Apple Health (HealthKit) — zero battery impact, no background service needed
- Refreshes on foreground resume and background app refresh

**Manual Edit**
- Set today's step total directly (e.g. "I walked 8,000 steps") rather than adding an increment
- Correction stored as an offset on top of the automatic count — sensor updates continue moving from where they left off
- Foreground notification and UI update immediately on edit
- Step counter card on the home screen with edit (✏️) and refresh (↺) buttons

**Date-Aware Step Counter**
- The step counter card on home and Nutrition screens is wired to the selected date
- **Today** — live mode with stream subscription, edit (offset-based), and refresh
- **Past date** — historical mode: loads the stored value from the `step_logs` row for that date, labelled "Steps · past day"
- Editing a past date writes the new value **directly** to that date's row (no offset logic, no cross-day contamination) so you can correct historical entries without affecting any other day

---

### Body Measurements
- Log waist, chest, arms, thighs, and any other dimension with date stamps
- Accessible from home screen Quick Access grid and from Progress screen
- Trend view per measurement type

---

### Wellness Log
- Daily entry for sleep hours, energy level (1–5), and soreness level (1–5)
- Optional notes per entry

---

### Supplements

**Daily Protocol**
- Accessible from the workout home navigation ("Supplements · Daily protocol")
- Add supplements with a name, optional dose (e.g. "75 mcg", "5 g", "1 softgel"), and a time of day
- **Today summary** — progress bar showing how many of the day's supplements have been taken (e.g. "3 / 5 taken")
- **Timeline grouping** — supplements auto-sorted into 🌅 Morning, ☀️ Midday, 🌆 Evening, and 🌙 Night buckets by their scheduled time
- Tap a supplement to mark it taken (green check); tap again to undo; long-press to edit
- **7-day adherence** shown per supplement (e.g. "5/7 days this week")

**Interactive Reminders**
- A daily reminder fires at each supplement's chosen time with two action buttons in the notification:
  - **✓ Taken** — logs the supplement as taken for today straight from the notification drawer, without opening the app; works even when the app is fully closed (handled in a background isolate). Logging is idempotent, so a double-tap is safe
  - **💤 Snooze** — opens the app to a quick picker (15 min / 30 min / 1 hour) that re-fires the same reminder after the chosen delay
- Tapping the notification body opens the Supplements screen
- If the Supplements screen is already open, marking a supplement taken from the notification updates the list live

---

### Notes
- Rich text editor (flutter_quill) for workout notes, thoughts, or anything else
- All notes stored locally in SQLite

---

### Settings & Data Management

**Export**
- **Export File** (CSV / JSON) — filtered by date range and optionally by a single exercise; date range respected for all data types including PRs, nutrition, body weight, wellness, steps, and measurements
- **Export to AI** — Markdown file with workouts, nutrition, wellness, PRs, and notes; respects the selected date range so you can export just "last week" for AI analysis
- **Full Backup** — exports everything (workouts, nutrition, custom foods, water logs, meal presets, body weight, wellness logs, achievements, exercise PRs, nutrition goals, step logs, body measurements, notes, meal templates, quick-start templates) as a single JSON file

**Restore from Backup**
- Import any Aawara JSON export — full backups or legacy workout-only exports
- Safe merge: existing entries are never overwritten; duplicates are skipped

**Profile & Notifications**
- Profile photo and name (set during onboarding, editable in settings)
- Configurable workout reminder notifications
- Interactive supplement reminders with Taken / Snooze actions (see Supplements)

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
| Step counting | pedometer + flutter_background_service |
| Health platform | health (Health Connect / HealthKit) |
| Data sharing | share_plus |
| File import | file_picker |
| Preferences | shared_preferences |
| ID generation | uuid |

**Theme**: Material 3, dark — `#0D0D1A` background, `#FFD700` gold accents, `#1A1A2E` card surfaces.

---

## Project Structure

```
lib/
├── main.dart
├── main_screen.dart                     # Bottom nav shell
├── splash_screen.dart
├── onboarding_screen.dart
├── home_screen.dart
├── settings_screen.dart
├── services/
│   ├── notification_service.dart       # Reminders + interactive supplement actions
│   ├── supplement_payload.dart         # Notification payload encode/decode (unit-tested)
│   ├── supplement_events.dart          # Live-refresh + pending-snooze signals
│   └── step_tracking_service.dart      # Android background service + iOS HealthKit
├── notes/
│   ├── note_model.dart
│   ├── notes_database.dart
│   ├── notes_list_screen.dart
│   └── note_editor_screen.dart
├── nutrition/
│   ├── models/
│   │   └── nutrition_models.dart       # Food, NutritionEntry, WaterLog, MealPreset, …
│   ├── screens/
│   │   ├── nutrition_screen.dart       # Dynamic meals, macro ring, editable entries
│   │   ├── nutrition_goals_screen.dart
│   │   ├── tdee_calculator_screen.dart # TDEE + custom goal overrides
│   │   ├── meal_presets_screen.dart
│   │   ├── barcode_scanner_screen.dart
│   │   └── add_custom_food_screen.dart
│   └── widgets/
│       ├── add_food_sheet.dart         # Food search, count/gram toggle, barcode
│       ├── edit_food_entry_sheet.dart  # Edit quantity + move to meal for logged entries
│       ├── meal_picker_sheet.dart      # Meal selector + create new meal
│       └── water_tracker_card.dart
└── workout/
    ├── database/
    │   └── workout_database.dart       # SQLite singleton, all migrations (v20)
    ├── models/
    │   ├── exercise.dart
    │   ├── workout_log.dart
    │   ├── supplement.dart             # Supplement + SupplementLog models
    │   └── workout_plan_day.dart
    ├── screens/
    │   ├── workout_home_screen.dart
    │   ├── quick_start_screen.dart
    │   ├── workout_logging_screen.dart
    │   ├── workout_complete_screen.dart
    │   ├── workout_history_screen.dart
    │   ├── workout_plan_screen.dart
    │   ├── exercise_library_screen.dart
    │   ├── supplements_screen.dart
    │   ├── progress_screen.dart
    │   ├── body_measurements_screen.dart
    │   ├── exercise_progress_screen.dart
    │   ├── exercise_progress_detail_screen.dart
    │   ├── monthly_summary_screen.dart
    │   ├── achievements_screen.dart
    │   ├── export_screen.dart
    │   └── step_goal_screen.dart
    └── widgets/
        ├── exercise_tile.dart
        ├── muscle_group_filter.dart
        ├── set_log_tile.dart
        ├── step_counter_card.dart      # Step count, edit, refresh
        ├── snooze_picker_sheet.dart     # Supplement snooze picker + root listener
        ├── workout_heatmap.dart
        └── empty_state_widget.dart
```

---

## Database

Single SQLite file (`workout.db`) managed by a singleton `WorkoutDatabase`. All migrations are strictly additive — existing user data is never dropped or modified without explicit user action.

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
| `body_measurements` | Per-type measurement history (waist, chest, etc.) |
| `exercise_prs` | Personal records per exercise (best 1RM) |
| `wellness_logs` | Daily sleep, energy, and soreness entries |
| `supplements` | User supplements (name, dose, reminder time, sort order) |
| `supplement_logs` | Per-day taken log, keyed by `(supplement_id, date)` |
| `achievements_unlocked` | Unlocked achievement IDs with timestamps |
| `foods` | Food library (~220 seeded foods + custom; includes sugar, sodium, sat fat, trans fat, cholesterol) |
| `nutrition_logs` | One row per date |
| `nutrition_entries` | Individual food items per meal per date |
| `nutrition_goals` | User-configured daily macro targets |
| `meal_templates` | Custom meal display names (meal_key → name) |
| `meal_slots` | Active meal slots with display order; drives which meals appear in the UI |
| `meal_presets` | Saved meal combos |
| `meal_preset_items` | Foods within a meal preset |
| `water_logs` | Daily water intake (glasses drunk + target) |
| `step_logs` | Daily step count and goal |
| `progress_photos` | Body progress photos with date |

Current schema version: **20**

---

## Getting Started

**Prerequisites**: Flutter 3.x, Android SDK (or Xcode for iOS)

```bash
cd aawara
flutter pub get
flutter run
```

**Run on Android**:
```bash
flutter devices
flutter run -d <device-id>
```

**Build release APK**:
```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

> Always use `adb install -r` (replace) — never uninstall, as the SQLite database lives in the app's private storage and will be lost on uninstall.

---

## Data Safety

All data is stored locally. The only outbound network request is the optional Open Food Facts barcode lookup — no personal data is sent, and it is only triggered when the user scans a barcode. The SQLite database lives in the app's private storage directory. Use **Full Backup** in Settings to export all your data as a JSON file at any time.

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
| 1.7 | Full data backup & restore — exports all user-data tables to a single JSON file; safe merge import with per-type result counts |
| 1.8 | Step tracking (Android foreground service + iOS HealthKit); Samsung Health Connect integration; manual step total override; step counter card on home screen |
| 1.9 | Dynamic meal system — numbered meals (Meal 1–5+), custom names, create/delete meal slots, meal picker when adding food; per-entry ⋮ menu (edit quantity, move to meal, delete); delete entire meal; decimal portion sizes; nutrition formula fix (correct per-serving scaling for all foods); extended nutrition fields (sugar, sodium, saturated fat, trans fat, cholesterol); TDEE custom goal overrides; AI export respects date range; body measurements quick-access tile; protein tile navigates to nutrition |
| 1.10 | Date-aware home screen — protein/calorie pill, water, wellness, weight, and step counter all reflect the selected date; new `getBodyWeightAsOf(date)` returns the as-of-date weight; step counter card now accepts a `date` param and switches between live and historical mode; historical step values are editable and write directly to that date's `step_logs` row; custom food create-form now stores values correctly (per-serving → per-100 g conversion); ⋮ menu on custom food rows in the search list (Edit / Delete); workout timer header redesigned — RUNNING / PAUSED badge with green/orange color coding, labeled Pause / Resume button, timer never auto-pauses on navigation; nut nutrition values corrected to USDA (Almonds, Cashews, Walnuts, Pistachios); two new milk variants added (Indian Cow / Buffalo milk without malai) |
| 1.11 | Interactive supplement reminders — daily notifications now carry **✓ Taken** and **💤 Snooze** action buttons; Taken logs the supplement straight from the drawer and works even when the app is killed (background isolate, idempotent on `supplement_logs`); Snooze opens an in-app 15m / 30m / 1h picker that re-fires the reminder; open Supplements screen refreshes live when marked from a notification; dedicated `supplement_reminders` channel; `ActionBroadcastReceiver` registered in the manifest so action taps reach Dart when backgrounded |
