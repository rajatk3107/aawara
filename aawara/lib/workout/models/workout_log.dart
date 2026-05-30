class SetLog {
  final String id;
  final String exerciseLogId;
  final int setNumber;
  final double? weight;
  final int? reps;
  final String? notes;
  final bool isCompleted;       // persisted checkmark
  // Cardio fields
  final int? durationSeconds;   // duration for cardio sets
  final double? speed;          // treadmill km/h, stair climber steps/min
  final double? incline;        // treadmill incline %
  final double? resistance;     // cross trainer / cycling resistance level
  final double? distanceKm;     // rowing / other cardio distance

  const SetLog({
    required this.id,
    required this.exerciseLogId,
    required this.setNumber,
    this.weight,
    this.reps,
    this.notes,
    this.isCompleted = false,
    this.durationSeconds,
    this.speed,
    this.incline,
    this.resistance,
    this.distanceKm,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'exercise_log_id': exerciseLogId,
        'set_number': setNumber,
        'weight': weight,
        'reps': reps,
        'notes': notes,
        'is_completed': isCompleted ? 1 : 0,
        'duration_seconds': durationSeconds,
        'speed': speed,
        'incline': incline,
        'resistance': resistance,
        'distance_km': distanceKm,
      };

  factory SetLog.fromMap(Map<String, dynamic> map) => SetLog(
        id: map['id'] as String,
        exerciseLogId: map['exercise_log_id'] as String,
        setNumber: map['set_number'] as int,
        weight: (map['weight'] as num?)?.toDouble(),
        reps: map['reps'] as int?,
        notes: map['notes'] as String?,
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        durationSeconds: map['duration_seconds'] as int?,
        speed: (map['speed'] as num?)?.toDouble(),
        incline: (map['incline'] as num?)?.toDouble(),
        resistance: (map['resistance'] as num?)?.toDouble(),
        distanceKm: (map['distance_km'] as num?)?.toDouble(),
      );

  SetLog copyWith({
    String? id,
    String? exerciseLogId,
    int? setNumber,
    double? weight,
    int? reps,
    String? notes,
    bool? isCompleted,
    int? durationSeconds,
    double? speed,
    double? incline,
    double? resistance,
    double? distanceKm,
  }) =>
      SetLog(
        id: id ?? this.id,
        exerciseLogId: exerciseLogId ?? this.exerciseLogId,
        setNumber: setNumber ?? this.setNumber,
        weight: weight ?? this.weight,
        reps: reps ?? this.reps,
        notes: notes ?? this.notes,
        isCompleted: isCompleted ?? this.isCompleted,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        speed: speed ?? this.speed,
        incline: incline ?? this.incline,
        resistance: resistance ?? this.resistance,
        distanceKm: distanceKm ?? this.distanceKm,
      );

  double get volume => (weight ?? 0) * (reps ?? 0);
}

class ExerciseLog {
  final String id;
  final String workoutLogId;
  final String exerciseId;
  final int orderIndex;
  final String? notes;
  final List<SetLog> sets;

  ExerciseLog({
    required this.id,
    required this.workoutLogId,
    required this.exerciseId,
    required this.orderIndex,
    this.notes,
    List<SetLog>? sets,
  }) : sets = sets ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'workout_log_id': workoutLogId,
        'exercise_id': exerciseId,
        'order_index': orderIndex,
        'notes': notes,
      };

  factory ExerciseLog.fromMap(Map<String, dynamic> map) => ExerciseLog(
        id: map['id'] as String,
        workoutLogId: map['workout_log_id'] as String,
        exerciseId: map['exercise_id'] as String,
        orderIndex: map['order_index'] as int,
        notes: map['notes'] as String?,
      );

  ExerciseLog copyWith({String? notes}) => ExerciseLog(
        id: id,
        workoutLogId: workoutLogId,
        exerciseId: exerciseId,
        orderIndex: orderIndex,
        notes: notes ?? this.notes,
        sets: sets,
      );

  double get totalVolume =>
      sets.fold(0.0, (sum, s) => sum + s.volume);
}

class WorkoutLog {
  final String id;
  final String date; // YYYY-MM-DD
  final String? planDayId;
  final String workoutName;
  final String? notes;
  final bool completed;
  final int? durationSeconds; // stored when workout is finished
  final List<ExerciseLog> exercises;

  WorkoutLog({
    required this.id,
    required this.date,
    this.planDayId,
    required this.workoutName,
    this.notes,
    this.completed = false,
    this.durationSeconds,
    List<ExerciseLog>? exercises,
  }) : exercises = exercises ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'plan_day_id': planDayId,
        'workout_name': workoutName,
        'notes': notes,
        'completed': completed ? 1 : 0,
        'duration_seconds': durationSeconds,
      };

  factory WorkoutLog.fromMap(Map<String, dynamic> map) => WorkoutLog(
        id: map['id'] as String,
        date: map['date'] as String,
        planDayId: map['plan_day_id'] as String?,
        workoutName: map['workout_name'] as String,
        notes: map['notes'] as String?,
        completed: (map['completed'] as int) == 1,
        durationSeconds: map['duration_seconds'] as int?,
      );

  WorkoutLog copyWith({
    String? id,
    String? date,
    String? planDayId,
    String? workoutName,
    String? notes,
    bool? completed,
    int? durationSeconds,
    List<ExerciseLog>? exercises,
  }) =>
      WorkoutLog(
        id: id ?? this.id,
        date: date ?? this.date,
        planDayId: planDayId ?? this.planDayId,
        workoutName: workoutName ?? this.workoutName,
        notes: notes ?? this.notes,
        completed: completed ?? this.completed,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        exercises: exercises ?? this.exercises,
      );

  int get totalSets => exercises.fold(0, (s, e) => s + e.sets.length);
  double get totalVolume => exercises.fold(0.0, (s, e) => s + e.totalVolume);
}
