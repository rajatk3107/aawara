class Supplement {
  final int? id;
  final String name;
  final String? dose; // e.g. "75 mcg", "5 g", "1 softgel"
  final String timeHhmm; // "HH:MM" 24h — used for reminders
  final String? notes;
  final int sortOrder;
  final String? createdAt;

  const Supplement({
    this.id,
    required this.name,
    this.dose,
    required this.timeHhmm,
    this.notes,
    this.sortOrder = 0,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'dose': dose,
        'time_hhmm': timeHhmm,
        'notes': notes,
        'sort_order': sortOrder,
      };

  factory Supplement.fromMap(Map<String, dynamic> m) => Supplement(
        id: m['id'] as int?,
        name: m['name'] as String,
        dose: m['dose'] as String?,
        timeHhmm: m['time_hhmm'] as String,
        notes: m['notes'] as String?,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        createdAt: m['created_at'] as String?,
      );

  Supplement copyWith({
    int? id,
    String? name,
    String? dose,
    String? timeHhmm,
    String? notes,
    int? sortOrder,
  }) =>
      Supplement(
        id: id ?? this.id,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        timeHhmm: timeHhmm ?? this.timeHhmm,
        notes: notes ?? this.notes,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}

class SupplementLog {
  final int supplementId;
  final String date; // YYYY-MM-DD
  final String takenAt; // ISO8601 timestamp

  const SupplementLog({
    required this.supplementId,
    required this.date,
    required this.takenAt,
  });

  Map<String, dynamic> toMap() => {
        'supplement_id': supplementId,
        'date': date,
        'taken_at': takenAt,
      };
}
