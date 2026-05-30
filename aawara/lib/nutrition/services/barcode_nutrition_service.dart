import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import 'open_food_facts_client.dart';
import 'nutrition_normalizer.dart';

// Provider chain (current → future):
//   1. Local DB (instant, offline)         ← implemented
//   2. Open Food Facts API (online)        ← implemented
//   3. [future] OCR / image-based lookup   ← add new provider here
//   4. [future] AI-powered nutrition est.  ← add new provider here
// Extend the chain in lookup() to add new data sources.

class BarcodeNutritionService {
  static final BarcodeNutritionService instance = BarcodeNutritionService._();
  BarcodeNutritionService._();

  final _client = OpenFoodFactsClient();
  final _normalizer = const NutritionNormalizer();

  Future<BarcodeScanResult> lookup(String barcode) async {
    final db = WorkoutDatabase.instance;

    // ── 1. Check scan cache — only skip API for confirmed 'found' entries ────
    // 'not_found' entries still re-query: the product may have gained nutrition
    // data on OFF since last scan (or was rejected due to a prior normalizer bug).
    final cached = await db.getScanCache(barcode);
    if (cached != null && cached.status == 'found' && cached.foodId != null) {
      final food = await db.getFoodById(cached.foodId!);
      if (food != null) {
        await db.incrementScanCount(barcode);
        return BarcodeFound(food, isFromLocal: true);
      }
    }

    // ── 2. Check local foods table by barcode ─────────────────────────────────
    final localFood = await db.getFoodByBarcode(barcode);
    if (localFood != null) {
      await db.upsertScanCache(ScanCacheEntry(
        barcode: barcode,
        foodId: localFood.id,
        status: 'found',
        scanCount: (cached?.scanCount ?? 0) + 1,
        lastScannedAt: DateTime.now().toIso8601String(),
      ));
      return BarcodeFound(localFood, isFromLocal: true);
    }

    // ── 3. Open Food Facts API ────────────────────────────────────────────────
    try {
      final product = await _client.lookupBarcode(barcode);
      if (product == null) {
        await db.upsertScanCache(ScanCacheEntry(
          barcode: barcode,
          status: 'not_found',
          scanCount: (cached?.scanCount ?? 0) + 1,
          lastScannedAt: DateTime.now().toIso8601String(),
        ));
        return BarcodeNotFound(barcode);
      }

      final result = _normalizer.normalize(barcode, product);
      if (result == null) {
        await db.upsertScanCache(ScanCacheEntry(
          barcode: barcode,
          status: 'not_found',
          scanCount: (cached?.scanCount ?? 0) + 1,
          lastScannedAt: DateTime.now().toIso8601String(),
        ));
        return BarcodeNotFound(barcode);
      }

      if (!result.isComplete) {
        // Product found on OFF but missing required macros — pass the partial
        // food as a pre-fill template. Don't save to DB or cache yet; the user
        // must complete the form before anything is persisted.
        return BarcodeFound(result.food,
            isFromLocal: false, isNutritionComplete: false);
      }

      final savedFood = await db.upsertFoodFromApi(result.food);
      await db.upsertScanCache(ScanCacheEntry(
        barcode: barcode,
        foodId: savedFood.id,
        status: 'found',
        scanCount: (cached?.scanCount ?? 0) + 1,
        lastScannedAt: DateTime.now().toIso8601String(),
        rawJson: jsonEncode(product),
      ));
      return BarcodeFound(savedFood, isFromLocal: false, isNutritionComplete: true);
    } on SocketException {
      return const BarcodeLookupError(
          'No internet connection. Check your network and try again.');
    } on TimeoutException {
      return const BarcodeLookupError(
          'Request timed out. Check your connection and try again.');
    } catch (_) {
      return const BarcodeLookupError('Lookup failed. Please try again.');
    }
  }
}
