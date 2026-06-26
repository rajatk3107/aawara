import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'samsung_health_models.dart';

/// Dart side of the Samsung Health native bridge. All methods no-op safely off
/// Android / non-Samsung devices.
class SamsungHealthService {
  SamsungHealthService._();
  static final SamsungHealthService instance = SamsungHealthService._();

  static const _channel = MethodChannel('aawara/samsung_health');

  /// True only on a Samsung device (Android 10+) with Samsung Health installed.
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Samsung Health's consent UI; returns the granted data-type names.
  Future<List<String>> requestPermissions() => _names('requestPermissions');

  Future<List<String>> grantedTypes() => _names('getGranted');

  Future<List<String>> _names(String method) async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<String>(method) ?? '[]';
      return (jsonDecode(raw) as List).cast<String>();
    } catch (e) {
      debugPrint('[samsung] $method failed: $e');
      return const [];
    }
  }

  Future<List<SamsungExercise>> readExercises(
          DateTime from, DateTime to) async =>
      _read('readExercises', from, to, SamsungExercise.fromJson);

  Future<List<SamsungSleep>> readSleep(DateTime from, DateTime to) async =>
      _read('readSleep', from, to, SamsungSleep.fromJson);

  Future<List<T>> _read<T>(String method, DateTime from, DateTime to,
      T Function(Map<dynamic, dynamic>) parse) async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<String>(method, {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      });
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .map((e) => parse(e as Map<dynamic, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[samsung] $method failed: $e');
      return const [];
    }
  }

  /// Heart-rate or SpO₂ samples in a window. [type] = 'HEART_RATE' | 'BLOOD_OXYGEN'.
  Future<List<({DateTime start, DateTime end, double v, double min, double max})>>
      readVitalSeries(String type, DateTime from, DateTime to) async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<String>('readVitalSeries', {
        'type': type,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      });
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List)
          .map((e) => (
                start: DateTime.parse(e['start'] as String),
                end: DateTime.parse(e['end'] as String),
                v: (e['v'] as num).toDouble(),
                min: (e['min'] as num).toDouble(),
                max: (e['max'] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      debugPrint('[samsung] readVitalSeries failed: $e');
      return const [];
    }
  }
}
