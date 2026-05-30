class PlateauAlert {
  final String exerciseId;
  final String exerciseName;
  final String muscleGroup;
  final double current1RM;
  final int weeksStagnant;
  final String suggestion;

  const PlateauAlert({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    required this.current1RM,
    required this.weeksStagnant,
    required this.suggestion,
  });
}
