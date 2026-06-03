class LabValue {
  final int? id;
  final String date; // YYYY-MM-DD
  final String name; // e.g. "TSH", "Free T4", "HbA1c"
  final double value;
  final String? unit; // e.g. "mIU/L", "ng/dL", "%"
  final double? refLow;
  final double? refHigh;
  final String? notes;
  final String? createdAt;

  const LabValue({
    this.id,
    required this.date,
    required this.name,
    required this.value,
    this.unit,
    this.refLow,
    this.refHigh,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'name': name,
        'value': value,
        'unit': unit,
        'ref_low': refLow,
        'ref_high': refHigh,
        'notes': notes,
      };

  factory LabValue.fromMap(Map<String, dynamic> m) => LabValue(
        id: m['id'] as int?,
        date: m['date'] as String,
        name: m['name'] as String,
        value: (m['value'] as num).toDouble(),
        unit: m['unit'] as String?,
        refLow: (m['ref_low'] as num?)?.toDouble(),
        refHigh: (m['ref_high'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
        createdAt: m['created_at'] as String?,
      );

  // Returns: null if no ref range, true if within, false if out of range
  bool? get inRange {
    if (refLow == null && refHigh == null) return null;
    if (refLow != null && value < refLow!) return false;
    if (refHigh != null && value > refHigh!) return false;
    return true;
  }
}
