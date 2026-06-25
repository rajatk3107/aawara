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
