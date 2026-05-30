class StepLog {
  final int? id;
  final String date;
  final int steps;
  final int goal;
  final String updatedAt;

  const StepLog({
    this.id,
    required this.date,
    required this.steps,
    required this.goal,
    required this.updatedAt,
  });

  double get progressPercent => goal > 0 ? steps / goal : 0;
  bool get goalMet => steps >= goal;
  double get distanceKm => steps * 0.000762;
  double get caloriesBurned => steps * 0.038;

  factory StepLog.fromMap(Map<String, dynamic> m) => StepLog(
        id: m['id'] as int?,
        date: m['date'] as String,
        steps: (m['steps'] as num).toInt(),
        goal: (m['goal'] as num).toInt(),
        updatedAt: m['updated_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'steps': steps,
        'goal': goal,
        'updated_at': updatedAt,
      };
}
