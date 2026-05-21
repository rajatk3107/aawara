class Food {
  final String id;
  final String name;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? fiberG;
  final double servingSize;
  final String servingUnit;
  final bool isCustom;

  const Food({
    required this.id,
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG,
    required this.servingSize,
    required this.servingUnit,
    required this.isCustom,
  });

  factory Food.fromMap(Map<String, dynamic> m) => Food(
        id: m['id'] as String,
        name: m['name'] as String,
        calories: (m['calories'] as num).toDouble(),
        proteinG: (m['protein_g'] as num).toDouble(),
        carbsG: (m['carbs_g'] as num).toDouble(),
        fatG: (m['fat_g'] as num).toDouble(),
        fiberG: (m['fiber_g'] as num?)?.toDouble(),
        servingSize: (m['serving_size'] as num).toDouble(),
        servingUnit: m['serving_unit'] as String,
        isCustom: (m['is_custom'] as int) == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'serving_size': servingSize,
        'serving_unit': servingUnit,
        'is_custom': isCustom ? 1 : 0,
      };
}

class NutritionGoals {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const NutritionGoals({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  factory NutritionGoals.fromMap(Map<String, dynamic> m) => NutritionGoals(
        calories: (m['calories'] as num).toDouble(),
        proteinG: (m['protein_g'] as num).toDouble(),
        carbsG: (m['carbs_g'] as num).toDouble(),
        fatG: (m['fat_g'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
      };

  static const NutritionGoals defaults = NutritionGoals(
    calories: 2000,
    proteinG: 150,
    carbsG: 200,
    fatG: 65,
  );
}

class NutritionEntry {
  final String id;
  final String logId;
  final Food food;
  final String mealType;
  final double quantity;
  final String createdAt;

  const NutritionEntry({
    required this.id,
    required this.logId,
    required this.food,
    required this.mealType,
    required this.quantity,
    required this.createdAt,
  });

  double get calories => food.calories * quantity;
  double get proteinG => food.proteinG * quantity;
  double get carbsG => food.carbsG * quantity;
  double get fatG => food.fatG * quantity;
  double get fiberG => (food.fiberG ?? 0) * quantity;
}

class NutritionTotals {
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final List<NutritionEntry> entries;

  const NutritionTotals({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.entries,
  });

  static const NutritionTotals empty = NutritionTotals(
    calories: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    fiberG: 0,
    entries: [],
  );
}

class WaterLog {
  final String date;
  final int glassesDrunk;
  final int targetGlasses;

  const WaterLog({
    required this.date,
    required this.glassesDrunk,
    required this.targetGlasses,
  });

  double get liters => glassesDrunk * 0.25;
  double get targetLiters => targetGlasses * 0.25;

  factory WaterLog.fromMap(Map<String, dynamic> m) => WaterLog(
        date: m['date'] as String,
        glassesDrunk: m['glasses_drunk'] as int,
        targetGlasses: m['target_glasses'] as int,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'glasses_drunk': glassesDrunk,
        'target_glasses': targetGlasses,
      };

  WaterLog copyWith({int? glassesDrunk, int? targetGlasses}) => WaterLog(
        date: date,
        glassesDrunk: glassesDrunk ?? this.glassesDrunk,
        targetGlasses: targetGlasses ?? this.targetGlasses,
      );
}

class MealPresetItem {
  final String id;
  final String presetId;
  final Food food;
  final double quantity;

  const MealPresetItem({
    required this.id,
    required this.presetId,
    required this.food,
    required this.quantity,
  });

  double get calories => food.calories * quantity;
  double get proteinG => food.proteinG * quantity;
  double get carbsG => food.carbsG * quantity;
  double get fatG => food.fatG * quantity;
}

class MealPreset {
  final String id;
  final String name;
  final String createdAt;
  final List<MealPresetItem> items;

  const MealPreset({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.items,
  });

  double get totalCalories =>
      items.fold(0.0, (s, i) => s + i.calories);
  double get totalProtein =>
      items.fold(0.0, (s, i) => s + i.proteinG);
}

class DailyNutritionSummary {
  final String date;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const DailyNutritionSummary({
    required this.date,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  factory DailyNutritionSummary.fromMap(Map<String, dynamic> m) =>
      DailyNutritionSummary(
        date: m['date'] as String,
        calories: (m['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (m['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (m['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (m['fat_g'] as num?)?.toDouble() ?? 0,
      );
}
