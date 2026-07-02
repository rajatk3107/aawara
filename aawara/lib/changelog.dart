/// In-app "What's New" history. Newest entry first; its [version] also drives
/// the one-time auto-show after an update (see MainScreen).
class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    version: '1.1.9',
    date: 'July 2026',
    changes: [
      'Exports now include the watch heart rate (avg/max/min) for every session, even ones Samsung didn’t store a summary for (e.g. weight machines) — matching what the workout screen shows',
    ],
  ),
  ChangelogEntry(
    version: '1.1.8',
    date: 'July 2026',
    changes: [
      'Heart-rate zones now use the standard 5-zone model (Zone 1–5, 95–190 bpm) instead of warm-up/fat-burn/cardio/peak',
      'HR chart redesigned: proper bpm axis, shaded fill, a marked peak, and a clearly-labelled average line',
      'Fixed the HR chart’s time axis — it now shows your local workout time instead of UTC',
    ],
  ),
  ChangelogEntry(
    version: '1.1.7',
    date: 'July 2026',
    changes: [
      'Workout Heart Rate card now shows a live HR line chart for the session (with your average marked)',
      'Heart rate now pulls the watch’s full HR stream for each workout — so sessions that showed no HR before (e.g. weight machines) now have their chart and zones',
    ],
  ),
  ChangelogEntry(
    version: '1.1.6',
    date: 'July 2026',
    changes: [
      'Workout view now shows every watch session for that workout (e.g. weights + treadmill) as a swipeable Heart Rate carousel',
      'Completed workouts scroll as one page — the heart-rate section is no longer stuck above a separate scroll',
      'Exports now list every watch session for a workout by name (weight machine, treadmill, …) with its heart-rate and calories',
    ],
  ),
  ChangelogEntry(
    version: '1.1.5',
    date: 'July 2026',
    changes: [
      'Completed workouts now show a Heart Rate card from your watch — average, max/min, and time in each zone (warm-up / fat-burn / cardio / peak)',
      'Past gym workouts link to the same-day watch session automatically',
      'Nothing changes on workouts without watch heart-rate data',
      'HR data now syncs incrementally — only new data since the last sync (faster, no repeated full pulls)',
      'Exports now include each workout’s watch heart-rate (avg/max, zones) and calories automatically — in CSV, JSON and the AI export',
    ],
  ),
  ChangelogEntry(
    version: '1.1.4',
    date: 'June 2026',
    changes: [
      'Connects to Samsung Health to pull watch workouts and sleep directly',
      'Watch workouts auto-link to the gym workouts you log — see HR, calories and distance next to your sets & reps',
      'Watch stats are included when you export a full backup'
    ],
  ),
  ChangelogEntry(
    version: '1.1.3',
    date: 'June 2026',
    changes: [
      'Rest timer now keeps running when you leave the workout screen and come back — it no longer disappears',
      'Rest countdown stays accurate across app backgrounding (anchored to real time, not screen ticks)',
      'Sleep data (score, stages & vitals) is now included in exports, AI export and full backup/restore',
    ],
  ),
  ChangelogEntry(
    version: '1.1.2',
    date: 'June 2026',
    changes: [
      'Sleep screen now shows a sleep-stages graph with time on the x-axis',
      'New overnight heart-rate and blood-oxygen line charts (with average and 90% marker)',
      'Stage breakdown now shows the typical healthy range for each stage',
    ],
  ),
  ChangelogEntry(
    version: '1.1.1',
    date: 'June 2026',
    changes: [
      'Sleep score is calculated with a new logic that is more accurate. It now factors in duration, deep, REM, light and awake time, plus SpO₂ and resting heart rate.',
      'More accurate sleep stage durations — fills gaps Health Connect leaves between stages',
      "What's New no longer pops up on launch; open it anytime from Settings → What's New",
    ],
  ),
  ChangelogEntry(
    version: '1.1.0',
    date: 'June 2026',
    changes: [
      'New Sleep screen — sleep stages, vitals and 7-day trend pulled from Health Connect',
      'Updated the sleep-score logic to closely match Samsung Health',
      'Sleep score now factors in duration, deep, REM, light and awake time, plus SpO₂ and resting heart rate',
      'Fixed supplement reminders — they now fire when the app is closed, the Snooze picker opens, and “Taken” works from the notification',
      'New 1RM calculator with a rep/percentage table',
      'Added this “What’s New” page',
    ],
  ),
];
