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
