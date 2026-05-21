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

    // ── 1. Check scan cache ───────────────────────────────────────────────────
    final cached = await db.getScanCache(barcode);
    if (cached != null) {
      if (cached.status == 'not_found') {
        await db.incrementScanCount(barcode);
        return BarcodeNotFound(barcode);
      }
      if (cached.foodId != null) {
        final food = await db.getFoodById(cached.foodId!);
        if (food != null) {
          await db.incrementScanCount(barcode);
          return BarcodeFound(food, isFromLocal: true);
        }
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

      final food = _normalizer.normalize(barcode, product);
      if (food == null) {
        await db.upsertScanCache(ScanCacheEntry(
          barcode: barcode,
          status: 'not_found',
          scanCount: (cached?.scanCount ?? 0) + 1,
          lastScannedAt: DateTime.now().toIso8601String(),
        ));
        return BarcodeNotFound(barcode);
      }

      final savedFood = await db.upsertFoodFromApi(food);
      await db.upsertScanCache(ScanCacheEntry(
        barcode: barcode,
        foodId: savedFood.id,
        status: 'found',
        scanCount: (cached?.scanCount ?? 0) + 1,
        lastScannedAt: DateTime.now().toIso8601String(),
        rawJson: jsonEncode(product),
      ));
      return BarcodeFound(savedFood, isFromLocal: false);
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
