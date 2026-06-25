import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/sleep_metrics.dart';

void main() {
  group('bedtimeOffset', () {
    DateTime at(int h, int m) => DateTime(2026, 6, 24, h, m);
    test('minutes after 9 PM, wrapping past midnight', () {
      expect(bedtimeOffset(at(21, 57)), 57); // 9:57 PM
      expect(bedtimeOffset(at(22, 15)), 75); // 10:15 PM
      expect(bedtimeOffset(at(22, 40)), 100); // 10:40 PM
      expect(bedtimeOffset(at(23, 6)), 126); // 11:06 PM
      expect(bedtimeOffset(at(0, 15)), 195); // 12:15 AM next day
    });
  });

  group('feature scoring functions', () {
    test('duration: 7–9h is perfect, short sleep cut', () {
      expect(scoreDuration(450), 1.0);
      expect(scoreDuration(420), 1.0);
      expect(scoreDuration(540), 1.0);
      expect(scoreDuration(405), closeTo(0.75, 0.001)); // 6.75h
      expect(scoreDuration(300), lessThan(0.4)); // 5h
    });

    test('deep: rises with minutes, plateaus at 90', () {
      expect(scoreDeep(90), 1.0);
      expect(scoreDeep(120), 1.0);
      expect(scoreDeep(31), closeTo(0.3 + 0.25 * 11 / 20, 0.001));
      expect(scoreDeep(10), lessThan(0.3));
    });

    test('rem: rises with minutes, plateaus at 120', () {
      expect(scoreRem(120), 1.0);
      expect(scoreRem(108), closeTo(0.8 + 0.2 * 18 / 30, 0.001));
      expect(scoreRem(20), lessThan(0.2));
    });

    test('awake: lenient, 58m still decent', () {
      expect(scoreAwake(15), 1.0);
      expect(scoreAwake(58), greaterThan(0.5));
      expect(scoreAwake(120), lessThanOrEqualTo(0.2));
    });

    test('latency: penalizes both extremes, optimal 8–20', () {
      expect(scoreLatency(15), 1.0);
      expect(scoreLatency(1), 0.60); // too fast
      expect(scoreLatency(40), 0.70);
      expect(scoreLatency(55), lessThan(0.70));
    });

    test('bedtime: optimal 9:55–10:30, late penalized', () {
      expect(scoreBedtime(57), 1.0); // 9:57 PM
      expect(scoreBedtime(100), 0.85); // 10:40 PM
      expect(scoreBedtime(126), lessThan(0.85)); // 11:06 PM
    });

    test('spo2: barely matters even with long dips', () {
      expect(scoreSpo2(0), 1.0);
      expect(scoreSpo2(23), 0.82); // worst case still 0.82
    });

    test('hr: best in 58–65 bpm', () {
      expect(scoreHr(60), 1.0);
      expect(scoreHr(64), 1.0);
      expect(scoreHr(72), lessThan(0.7));
    });
  });

  group('computeSleepScore vs Samsung (end-to-end)', () {
    // Full inputs for the today/25-Jun night where all 8 metrics are known.
    test('today night lands near Samsung 79', () {
      final score = computeSleepScore(
        actualSleepMinutes: 383,
        deepSleepMinutes: 31,
        remSleepMinutes: 108,
        awakeMinutes: 58,
        latencyMinutes: 18,
        bedtime: DateTime(2026, 6, 24, 22, 40), // 10:40 PM
        avgHrBpm: 64,
        spo2DipMinutes: 6.5,
      );
      expect((score - 79).abs(), lessThanOrEqualTo(5));
    });

    test('clamps to the 50–100 band', () {
      final terrible = computeSleepScore(
        actualSleepMinutes: 120,
        deepSleepMinutes: 0,
        remSleepMinutes: 0,
        awakeMinutes: 120,
        latencyMinutes: 90,
        bedtime: DateTime(2026, 6, 24, 2, 0), // 2 AM
        avgHrBpm: 80,
        spo2DipMinutes: 30,
      );
      expect(terrible, greaterThanOrEqualTo(50));
      final great = computeSleepScore(
        actualSleepMinutes: 480,
        deepSleepMinutes: 100,
        remSleepMinutes: 130,
        awakeMinutes: 15,
        latencyMinutes: 12,
        bedtime: DateTime(2026, 6, 24, 22, 0),
        avgHrBpm: 60,
        spo2DipMinutes: 0,
      );
      expect(great, lessThanOrEqualTo(100));
      expect(great, greaterThan(terrible));
    });

    test('returns 0 with no sleep', () {
      expect(
        computeSleepScore(
          actualSleepMinutes: 0,
          deepSleepMinutes: 0,
          remSleepMinutes: 0,
          awakeMinutes: 0,
          latencyMinutes: 0,
          bedtime: DateTime(2026, 6, 24, 22, 0),
          avgHrBpm: 60,
          spo2DipMinutes: 0,
        ),
        0,
      );
    });
  });

  group('labels', () {
    test('overall label bands', () {
      expect(sleepScoreLabel(92), 'Excellent');
      expect(sleepScoreLabel(82), 'Good');
      expect(sleepScoreLabel(72), 'Fair');
      expect(sleepScoreLabel(60), 'Needs attention');
    });

    test('per-factor label bands', () {
      expect(factorLabel(0.97), 'Excellent');
      expect(factorLabel(0.85), 'Good');
      expect(factorLabel(0.65), 'Fair');
      expect(factorLabel(0.4), 'Attention');
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
