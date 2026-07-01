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
    version: '1.1.5',
    date: 'July 2026',
    changes: [
      'Completed workouts now show a Heart Rate card from your watch — average, max/min, and time in each zone (warm-up / fat-burn / cardio / peak)',
      'Past gym workouts link to the same-day watch session automatically',
      'Nothing changes on workouts without watch heart-rate data',
      'Samsung Health now syncs incrementally — only new data since the last sync (faster, no repeated full pulls)',
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
