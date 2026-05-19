class Exercise {
  final String id;
  final String name;
  final String muscleGroup;
  final String equipment;
  final bool isCustom;
  final String exerciseType; // 'strength' or 'cardio'

  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    this.isCustom = false,
    this.exerciseType = 'strength',
  });

  bool get isCardio => exerciseType == 'cardio';

  CardioType get cardioType {
    switch (equipment.toLowerCase()) {
      case 'treadmill':
        return CardioType.treadmill;
      case 'cross trainer':
      case 'elliptical':
        return CardioType.crossTrainer;
      case 'cycling':
      case 'bike':
      case 'stationary bike':
        return CardioType.cycling;
      case 'rowing machine':
        return CardioType.rowing;
      case 'stair climber':
        return CardioType.stairClimber;
      default:
        return CardioType.other;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'muscle_group': muscleGroup,
        'equipment': equipment,
        'is_custom': isCustom ? 1 : 0,
        'exercise_type': exerciseType,
      };

  factory Exercise.fromMap(Map<String, dynamic> map) => Exercise(
        id: map['id'] as String,
        name: map['name'] as String,
        muscleGroup: map['muscle_group'] as String,
        equipment: map['equipment'] as String,
        isCustom: (map['is_custom'] as int) == 1,
        exerciseType: (map['exercise_type'] as String?) ?? 'strength',
      );

  Exercise copyWith({
    String? id,
    String? name,
    String? muscleGroup,
    String? equipment,
    bool? isCustom,
    String? exerciseType,
  }) =>
      Exercise(
        id: id ?? this.id,
        name: name ?? this.name,
        muscleGroup: muscleGroup ?? this.muscleGroup,
        equipment: equipment ?? this.equipment,
        isCustom: isCustom ?? this.isCustom,
        exerciseType: exerciseType ?? this.exerciseType,
      );
}

enum CardioType { treadmill, crossTrainer, cycling, rowing, stairClimber, other }

const List<String> kMuscleGroups = [
  'Chest',
  'Back',
  'Shoulders',
  'Arms',
  'Legs',
  'Core',
  'Cardio',
  'Full Body',
];

const List<String> kEquipmentTypes = [
  'Barbell',
  'Dumbbell',
  'Cable',
  'Machine',
  'Bodyweight',
  'Kettlebell',
  'Resistance Band',
  'Other',
];

const List<String> kCardioMachineTypes = [
  'Treadmill',
  'Cross Trainer',
  'Cycling',
  'Rowing Machine',
  'Stair Climber',
  'Other',
];
