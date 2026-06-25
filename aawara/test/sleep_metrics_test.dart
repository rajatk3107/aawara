import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/sleep_metrics.dart';

void main() {
  group('computeSleepScore', () {
    test('returns 0 when there is no sleep', () {
      expect(
        computeSleepScore(asleep: 0, deep: 0, rem: 0, awake: 0, total: 0),
        0,
      );
    });

    test('a solid night scores high', () {
      // 7.5h asleep, ~18% deep, ~22% REM, little awake.
      final score = computeSleepScore(
        asleep: 450,
        deep: 81,
        rem: 99,
        awake: 30,
        total: 480,
      );
      expect(score, greaterThanOrEqualTo(90));
      expect(score, lessThanOrEqualTo(100));
    });

    test('a short, fragmented night scores low', () {
      final low = computeSleepScore(
        asleep: 180, deep: 10, rem: 10, awake: 120, total: 300);
      final good = computeSleepScore(
        asleep: 450, deep: 81, rem: 99, awake: 30, total: 480);
      expect(low, lessThan(good));
    });

    test('never exceeds 100 even with abundant deep/REM and long sleep', () {
      final score = computeSleepScore(
        asleep: 600, deep: 300, rem: 300, awake: 0, total: 600);
      expect(score, lessThanOrEqualTo(100));
    });
  });

  group('sleep score vs Samsung (end-to-end)', () {
    // Full stage data + Samsung score for 4 nights (22–25 Jun 2026), the data
    // the model + calibration were fit to.
    // (asleep, deep, rem, awake, timeInBed, samsungScore)
    const nights = [
      (445, 72, 144, 38, 483, 91), // 22 Jun
      (418, 68, 108, 37, 455, 88), // 23 Jun
      (339, 69, 106, 31, 370, 71), // 24 Jun
      (383, 31, 108, 58, 441, 79), // 25 Jun
    ];

    int ourScore((int, int, int, int, int, int) n) =>
        calibrateSleepScore(computeSleepScore(
            asleep: n.$1, deep: n.$2, rem: n.$3, awake: n.$4, total: n.$5));

    test('matches Samsung within a few points on the fitted nights', () {
      var total = 0, maxErr = 0;
      for (final n in nights) {
        final err = (ourScore(n) - n.$6).abs();
        total += err;
        if (err > maxErr) maxErr = err;
      }
      expect(total / nights.length, lessThan(2.5)); // mean abs error
      expect(maxErr, lessThanOrEqualTo(4));
    });
  });

  group('calibrateSleepScore basics', () {
    test('maps an empty night to 0', () => expect(calibrateSleepScore(0), 0));
    test('stays within 0..100', () {
      expect(calibrateSleepScore(100), lessThanOrEqualTo(100));
      expect(calibrateSleepScore(100), greaterThan(0));
    });
  });

  group('rangeFactor', () {
    test('full marks inside the range', () {
      expect(rangeFactor(0.18, 0.14, 0.24), 1.0);
      expect(rangeFactor(0.14, 0.14, 0.24), 1.0); // inclusive low
      expect(rangeFactor(0.24, 0.14, 0.24), 1.0); // inclusive high
    });

    test('cuts proportionally below the range', () {
      // 0.07 is half the falloff (0.14) below the low bound -> 0.5
      expect(rangeFactor(0.07, 0.14, 0.24, falloff: 0.14), closeTo(0.5, 0.001));
      expect(rangeFactor(0.0, 0.14, 0.24, falloff: 0.14), 0.0);
    });

    test('cuts proportionally above the range', () {
      // 0.31 is 0.07 above the high bound, falloff 0.14 -> 0.5
      expect(rangeFactor(0.31, 0.14, 0.24, falloff: 0.14), closeTo(0.5, 0.001));
    });

    test('never goes negative', () {
      expect(rangeFactor(0.6, 0.14, 0.24, falloff: 0.14), 0.0);
    });
  });

  group('computeSleepScore range behaviour', () {
    test('in-range deep+REM beats out-of-range with the same duration', () {
      final inRange = computeSleepScore(
          asleep: 450, deep: 81, rem: 99, awake: 30, total: 480); // 18%, 22%
      final tooLittle = computeSleepScore(
          asleep: 450, deep: 9, rem: 9, awake: 30, total: 480); // 2%, 2%
      final tooMuch = computeSleepScore(
          asleep: 450, deep: 225, rem: 225, awake: 30, total: 480); // 50%, 50%
      expect(inRange, greaterThan(tooLittle));
      expect(inRange, greaterThan(tooMuch));
    });
  });

  group('vitalsPenalty', () {
    test('no penalty when vitals are missing', () {
      expect(vitalsPenalty(spo2Avg: null, restingHr: null), 0);
    });

    test('no penalty for healthy vitals', () {
      expect(vitalsPenalty(spo2Avg: 96, restingHr: 52), 0);
    });

    test('penalizes low blood oxygen', () {
      expect(vitalsPenalty(spo2Avg: 90, restingHr: 52), 5); // (92-90)*2.5
    });

    test('caps the blood-oxygen penalty for very low SpO2', () {
      expect(vitalsPenalty(spo2Avg: 80, restingHr: 52), 15); // capped
    });

    test('penalizes an elevated resting heart rate', () {
      expect(vitalsPenalty(spo2Avg: 96, restingHr: 70), 4); // (70-62)*0.5
    });

    test('combines penalties but caps the total', () {
      expect(vitalsPenalty(spo2Avg: 85, restingHr: 90), 20); // capped at 20
    });
  });

  group('aggregateStages', () {
    DateTime t(int h, int m) => DateTime(2026, 6, 24, h, m);

    test('sums minutes per stage', () {
      final totals = aggregateStages([
        SleepStageSegment(SleepStage.light, t(22, 40), t(23, 0)), // 20m
        SleepStageSegment(SleepStage.awake, t(23, 0), t(23, 3)), //  3m
        SleepStageSegment(SleepStage.deep, t(23, 3), t(23, 18)), // 15m
        SleepStageSegment(SleepStage.rem, t(23, 18), t(23, 48)), // 30m
        SleepStageSegment(SleepStage.light, t(23, 48), t(23, 58)), // 10m
      ]);
      expect(totals.lightMinutes, 30);
      expect(totals.awakeMinutes, 3);
      expect(totals.deepMinutes, 15);
      expect(totals.remMinutes, 30);
    });

    test('orders the timeline by start time across midnight', () {
      // 10:40 PM precedes 1:00 AM the next day.
      final totals = aggregateStages([
        SleepStageSegment(SleepStage.deep,
            DateTime(2026, 6, 25, 1, 0), DateTime(2026, 6, 25, 1, 20)),
        SleepStageSegment(SleepStage.light, t(22, 40), t(23, 0)),
      ]);
      expect(totals.timeline.first.stage, SleepStage.light);
      expect(totals.timeline.last.stage, SleepStage.deep);
    });

    test('handles an empty list', () {
      final totals = aggregateStages([]);
      expect(totals.lightMinutes, 0);
      expect(totals.timeline, isEmpty);
    });
  });
}
