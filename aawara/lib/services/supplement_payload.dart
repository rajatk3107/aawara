/// Encodes/decodes the notification payload used by interactive supplement
/// reminders so action handlers know which supplement was acted on.
///
/// Format: `supp|<id>|<name>|<dose>`. The `|` delimiter is stripped from the
/// free-text name and dose before encoding so it can never corrupt parsing.
library;

class SupplementPayload {
  final int id;
  final String name;
  final String? dose;
  const SupplementPayload({required this.id, required this.name, this.dose});
}

const _prefix = 'supp';
const _delimiter = '|';

String _sanitize(String s) => s.replaceAll(_delimiter, '/');

String encodeSupplementPayload({
  required int id,
  required String name,
  String? dose,
}) {
  return [
    _prefix,
    id.toString(),
    _sanitize(name),
    _sanitize(dose ?? ''),
  ].join(_delimiter);
}

SupplementPayload? decodeSupplementPayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(_delimiter);
  if (parts.length < 4 || parts[0] != _prefix) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  final name = parts[2];
  final dose = parts[3].isEmpty ? null : parts[3];
  return SupplementPayload(id: id, name: name, dose: dose);
}
