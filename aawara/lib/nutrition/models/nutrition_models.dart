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
  final String? barcode;
  final String? brand;
  final double? sugarG;
  final double? sodiumMg;
  final double? saturatedFatG;
  final double? transFatG;
  final double? cholesterolMg;
  final String? source;
  final String? lastUpdated;

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
    this.barcode,
    this.brand,
    this.sugarG,
    this.sodiumMg,
    this.saturatedFatG,
    this.transFatG,
    this.cholesterolMg,
    this.source,
    this.lastUpdated,
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
        barcode: m['barcode'] as String?,
        brand: m['brand'] as String?,
        sugarG: (m['sugar_g'] as num?)?.toDouble(),
        sodiumMg: (m['sodium_mg'] as num?)?.toDouble(),
        saturatedFatG: (m['saturated_fat_g'] as num?)?.toDouble(),
        transFatG: (m['trans_fat_g'] as num?)?.toDouble(),
        cholesterolMg: (m['cholesterol_mg'] as num?)?.toDouble(),
        source: m['source'] as String?,
        lastUpdated: m['last_updated'] as String?,
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
        'barcode': barcode,
        'brand': brand,
        'sugar_g': sugarG,
        'sodium_mg': sodiumMg,
        'saturated_fat_g': saturatedFatG,
        'trans_fat_g': transFatG,
        'cholesterol_mg': cholesterolMg,
        'source': source,
        'last_updated': lastUpdated,
      };

  Food copyWith({
    String? id,
    String? name,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? servingSize,
    String? servingUnit,
    bool? isCustom,
    String? barcode,
    String? brand,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? transFatG,
    double? cholesterolMg,
    String? source,
    String? lastUpdated,
  }) =>
      Food(
        id: id ?? this.id,
        name: name ?? this.name,
        calories: calories ?? this.calories,
        proteinG: proteinG ?? this.proteinG,
        carbsG: carbsG ?? this.carbsG,
        fatG: fatG ?? this.fatG,
        fiberG: fiberG ?? this.fiberG,
        servingSize: servingSize ?? this.servingSize,
        servingUnit: servingUnit ?? this.servingUnit,
        isCustom: isCustom ?? this.isCustom,
        barcode: barcode ?? this.barcode,
        brand: brand ?? this.brand,
        sugarG: sugarG ?? this.sugarG,
        sodiumMg: sodiumMg ?? this.sodiumMg,
        saturatedFatG: saturatedFatG ?? this.saturatedFatG,
        transFatG: transFatG ?? this.transFatG,
        cholesterolMg: cholesterolMg ?? this.cholesterolMg,
        source: source ?? this.source,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

class ScanCacheEntry {
  final String barcode;
  final String? foodId;
  final String status;
  final int scanCount;
  final String lastScannedAt;
  final String? rawJson;

  const ScanCacheEntry({
    required this.barcode,
    this.foodId,
    required this.status,
    this.scanCount = 1,
    required this.lastScannedAt,
    this.rawJson,
  });

  factory ScanCacheEntry.fromMap(Map<String, dynamic> m) => ScanCacheEntry(
        barcode: m['barcode'] as String,
        foodId: m['food_id'] as String?,
        status: m['status'] as String,
        scanCount: m['scan_count'] as int,
        lastScannedAt: m['last_scanned_at'] as String,
        rawJson: m['raw_json'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'barcode': barcode,
        'food_id': foodId,
        'status': status,
        'scan_count': scanCount,
        'last_scanned_at': lastScannedAt,
        'raw_json': rawJson,
      };
}

sealed class BarcodeScanResult {
  const BarcodeScanResult();
}

class BarcodeFound extends BarcodeScanResult {
  final Food food;
  final bool isFromLocal;
  // false = one or more required macros (cal/protein/carbs/fat) were absent
  // on OFF — show pre-filled editable form before saving.
  final bool isNutritionComplete;
  const BarcodeFound(this.food,
      {required this.isFromLocal, this.isNutritionComplete = true});
}

class BarcodeNotFound extends BarcodeScanResult {
  final String barcode;
  const BarcodeNotFound(this.barcode);
}

class BarcodeLookupError extends BarcodeScanResult {
  final String message;
  const BarcodeLookupError(this.message);
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
