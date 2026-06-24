import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/one_rep_max.dart';

void main() {
  group('epleyOneRepMax', () {
    test('a true single returns the weight itself', () {
      expect(epleyOneRepMax(100, 1), 100);
    });

    test('uses the Epley formula for multi-rep sets', () {
      // 100 * (1 + 5/30) = 116.666...
      expect(epleyOneRepMax(100, 5), closeTo(116.667, 0.01));
    });

    test('returns 0 for non-positive weight or reps', () {
      expect(epleyOneRepMax(0, 5), 0);
      expect(epleyOneRepMax(100, 0), 0);
      expect(epleyOneRepMax(-50, 5), 0);
    });
  });

  group('repMaxTable', () {
    test('covers the working-rep targets in order', () {
      final table = repMaxTable(100);
      expect(table.map((t) => t.reps).toList(), [2, 3, 5, 8, 10, 12]);
    });

    test('computes percentages from the Epley inverse', () {
      final table = repMaxTable(100);
      final byReps = {for (final t in table) t.reps: t};
      expect(byReps[2]!.percent, 94); // 1/(1+2/30) = 93.75% -> 94
      expect(byReps[5]!.percent, 86); // 85.7% -> 86
      expect(byReps[10]!.percent, 75); // exactly 75%
      expect(byReps[12]!.percent, 71); // 71.4% -> 71
    });

    test('rounds weights to the nearest 0.5 kg', () {
      final table = repMaxTable(100);
      final byReps = {for (final t in table) t.reps: t};
      expect(byReps[2]!.weight, 94.0); // 93.75 -> 94.0
      expect(byReps[5]!.weight, 85.5); // 85.71 -> 85.5
      expect(byReps[10]!.weight, 75.0);
      expect(byReps[12]!.weight, 71.5); // 71.43 -> 71.5
    });

    test('returns an empty table for a non-positive 1RM', () {
      expect(repMaxTable(0), isEmpty);
    });
  });
}
