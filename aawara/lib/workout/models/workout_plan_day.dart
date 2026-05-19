class WorkoutPlanDay {
  final String id;
  final int dayOfWeek; // 1=Monday, 7=Sunday
  final String workoutName;
  final bool isRestDay;
  final List<String> exerciseIds;

  const WorkoutPlanDay({
    required this.id,
    required this.dayOfWeek,
    required this.workoutName,
    this.isRestDay = false,
    this.exerciseIds = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'day_of_week': dayOfWeek,
        'workout_name': workoutName,
        'is_rest_day': isRestDay ? 1 : 0,
      };

  factory WorkoutPlanDay.fromMap(Map<String, dynamic> map) => WorkoutPlanDay(
        id: map['id'] as String,
        dayOfWeek: map['day_of_week'] as int,
        workoutName: map['workout_name'] as String,
        isRestDay: (map['is_rest_day'] as int) == 1,
      );

  WorkoutPlanDay copyWith({
    String? id,
    int? dayOfWeek,
    String? workoutName,
    bool? isRestDay,
    List<String>? exerciseIds,
  }) =>
      WorkoutPlanDay(
        id: id ?? this.id,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        workoutName: workoutName ?? this.workoutName,
        isRestDay: isRestDay ?? this.isRestDay,
        exerciseIds: exerciseIds ?? this.exerciseIds,
      );
}

const List<String> kDayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> kDayAbbreviations = [
  'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN',
];
