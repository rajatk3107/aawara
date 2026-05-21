import 'package:uuid/uuid.dart';
import '../models/nutrition_models.dart';

class NormalizationResult {
  final Food food;
  // true only when ALL four required macros were explicitly present in OFF data
  final bool isComplete;

  const NormalizationResult({required this.food, required this.isComplete});
}

class NutritionNormalizer {
  const NutritionNormalizer();

  // Returns null only if the product has no usable name.
  // isComplete is false when any required macro (cal/protein/carbs/fat) was
  // absent from OFF — the UI should then ask the user to fill in the gaps.
  NormalizationResult? normalize(String barcode, Map<String, dynamic> product) {
    final nutriments = (product['nutriments'] as Map<String, dynamic>?) ?? {};

    final name = ((product['product_name'] as String?) ??
            (product['product_name_en'] as String?) ??
            '')
        .trim();
    if (name.isEmpty) return null;

    final brand = (product['brands'] as String?)
        ?.split(',')
        .first
        .trim()
        .nullIfEmpty();

    // Track explicit presence separately from the value itself
    final calRaw = _d(nutriments['energy-kcal_100g']) ??
        (_d(nutriments['energy_100g']) != null
            ? _d(nutriments['energy_100g'])! / 4.184
            : null);
    final proteinRaw = _d(nutriments['proteins_100g']);
    final carbsRaw = _d(nutriments['carbohydrates_100g']);
    final fatRaw = _d(nutriments['fat_100g']);

    final isComplete =
        calRaw != null && proteinRaw != null && carbsRaw != null && fatRaw != null;

    final fiberPer100g = _d(nutriments['fiber_100g']);
    final sugarPer100g = _d(nutriments['sugars_100g']);
    final sodiumMgPer100g =
        _d(nutriments['sodium_100g']) != null ? _d(nutriments['sodium_100g'])! * 1000 : null;

    // Parse serving size string like "30g", "1 cup (240 ml)", "1 tbsp (15g)"
    final servingSizeStr = product['serving_size'] as String?;
    double servingSize = 100.0;
    String servingUnit = 'g';
    if (servingSizeStr != null && servingSizeStr.isNotEmpty) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*(g|ml|oz)', caseSensitive: false)
          .firstMatch(servingSizeStr);
      if (match != null) {
        servingSize = double.tryParse(match.group(1)!) ?? 100.0;
        servingUnit = match.group(2)!.toLowerCase();
      }
    }

    final food = Food(
      id: const Uuid().v4(),
      name: name,
      calories: calRaw ?? 0.0,
      proteinG: proteinRaw ?? 0.0,
      carbsG: carbsRaw ?? 0.0,
      fatG: fatRaw ?? 0.0,
      fiberG: fiberPer100g,
      servingSize: servingSize,
      servingUnit: servingUnit,
      isCustom: false,
      barcode: barcode,
      brand: brand,
      sugarG: sugarPer100g,
      sodiumMg: sodiumMgPer100g,
      source: 'off',
      lastUpdated: DateTime.now().toIso8601String(),
    );

    return NormalizationResult(food: food, isComplete: isComplete);
  }

  double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

extension _StringExt on String {
  String? nullIfEmpty() => isEmpty ? null : this;
}
