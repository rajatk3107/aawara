import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/rest_timer.dart';

void main() {
  group('restRemainingSeconds', () {
    final now = DateTime(2026, 6, 26, 10, 0, 0);

    test('returns 0 when there is no active rest', () {
      expect(restRemainingSeconds(null, now), 0);
    });

    test('returns the full duration just after a rest starts', () {
      final end = now.add(const Duration(seconds: 90));
      expect(restRemainingSeconds(end, now), 90);
    });

    test('counts down with elapsed wall-clock time', () {
      final end = now.add(const Duration(seconds: 90));
      // 30s have passed while the screen was away.
      final later = now.add(const Duration(seconds: 30));
      expect(restRemainingSeconds(end, later), 60);
    });

    test('rounds a partial second up so the last second still shows', () {
      final end = now.add(const Duration(milliseconds: 1500));
      expect(restRemainingSeconds(end, now), 2);
    });

    test('returns 0 once the rest has fully elapsed', () {
      final end = now.add(const Duration(seconds: 90));
      final after = now.add(const Duration(seconds: 91));
      expect(restRemainingSeconds(end, after), 0);
    });

    test('returns 0 (never negative) well past the end', () {
      final end = now.add(const Duration(seconds: 90));
      final wayAfter = now.add(const Duration(minutes: 10));
      expect(restRemainingSeconds(end, wayAfter), 0);
    });
  });
}
