/// A queue of "supplement taken" actions captured from notification action
/// buttons while the app was backgrounded or killed.
///
/// The notification action runs in the plugin's separate FlutterEngine, which
/// does NOT have native plugins (sqflite) registered — so it cannot write to the
/// database directly. Instead it appends `id,date` lines to a plain file (via
/// dart:io, which needs no plugins), and the main isolate drains them into the
/// database on next launch/resume.
library;

class PendingTaken {
  final int id;
  final String date;
  const PendingTaken(this.id, this.date);
}

String formatPendingTakenLine(int id, String date) => '$id,$date';

List<PendingTaken> parsePendingTaken(String contents) {
  final out = <PendingTaken>[];
  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(',');
    if (parts.length != 2) continue;
    final id = int.tryParse(parts[0]);
    final date = parts[1].trim();
    if (id == null || date.isEmpty) continue;
    out.add(PendingTaken(id, date));
  }
  return out;
}
