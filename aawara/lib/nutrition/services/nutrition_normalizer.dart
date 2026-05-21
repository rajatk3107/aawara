import 'package:uuid/uuid.dart';
import '../models/nutrition_models.dart';

class NutritionNormalizer {
  const NutritionNormalizer();

  // Converts an OFF product JSON object into a Food, or returns null if data
  // is insufficient (missing name, zero / missing calories).
  Food? normalize(String barcode, Map<String, dynamic> product) {
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

    // Energy — prefer kcal field, fall back to kJ ÷ 4.184
    final calPer100g = _d(nutriments['energy-kcal_100g']) ??
        (_d(nutriments['energy_100g']) != null
            ? _d(nutriments['energy_100g'])! / 4.184
            : null) ??
        0.0;
    if (calPer100g <= 0) return null;

    final proteinPer100g = _d(nutriments['proteins_100g']) ?? 0.0;
    final carbsPer100g = _d(nutriments['carbohydrates_100g']) ?? 0.0;
    final fatPer100g = _d(nutriments['fat_100g']) ?? 0.0;
    final fiberPer100g = _d(nutriments['fiber_100g']);
    final sugarPer100g = _d(nutriments['sugars_100g']);
    // OFF stores sodium in g/100g; convert to mg
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

    return Food(
      id: const Uuid().v4(),
      name: name,
      calories: calPer100g,
      proteinG: proteinPer100g,
      carbsG: carbsPer100g,
      fatG: fatPer100g,
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
