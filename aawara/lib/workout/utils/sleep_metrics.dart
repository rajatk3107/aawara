/// Pure sleep-metric helpers, isolated from the `health` plugin so they can be
/// unit-tested. The service maps Health Connect data points into these plain
/// value types before calling in.
library;

enum SleepStage { awake, rem, light, deep }

class SleepStageSegment {
  final SleepStage stage;
  final DateTime start;
  final DateTime end;
  const SleepStageSegment(this.stage, this.start, this.end);

  int get minutes => end.difference(start).inMinutes;
}

class SleepStageTotals {
  final int awakeMinutes;
  final int remMinutes;
  final int lightMinutes;
  final int deepMinutes;

  /// Segments ordered by start time, for drawing the hypnogram.
  final List<SleepStageSegment> timeline;

  const SleepStageTotals({
    required this.awakeMinutes,
    required this.remMinutes,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.timeline,
  });

  int get asleepMinutes => remMinutes + lightMinutes + deepMinutes;
}

/// 1.0 when [value] is within [low, high], falling linearly to 0 as it moves
/// [falloff] beyond either bound (default: the [low] bound's width).
double rangeFactor(double value, double low, double high, {double? falloff}) {
  if (value >= low && value <= high) return 1.0;
  final f = falloff ?? low;
  if (f <= 0) return 0.0;
  final dist = value < low ? low - value : value - high;
  return (1 - dist / f).clamp(0.0, 1.0);
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

/// Our own transparent 0–100 raw sleep score, then mapped to Samsung's scale by
/// [calibrateSleepScore]. Weighted across five factors, with actual sleep
/// duration dominant (Samsung's score tracks it strongly):
///
///  * Duration (60): actual sleep time, 3h→0 … 7.5h→full.
///  * Deep (12): proportion of sleep in the 13–18% healthy band.
///  * REM (13): absolute REM minutes, 50→0 … 110+→full.
///  * Light (5): proportion of sleep in the 45–60% band.
///  * Efficiency (10): asleep ÷ time-in-bed, 75%→0 … 92%→full.
///
/// [asleep] is light+deep+rem; [total] is time in bed. Returns 0 for an empty
/// night.
int computeSleepScore({
  required int asleep,
  required int deep,
  required int rem,
  required int awake,
  required int total,
}) {
  if (asleep <= 0 || total <= 0) return 0;

  final light = (asleep - deep - rem).clamp(0, asleep);
  final deepP = deep / asleep;
  final remMin = rem.toDouble();
  final lightP = light / asleep;
  final efficiency = asleep / total;

  final durationScore = 60 * _clamp01((asleep - 180) / 270); // 3h..7.5h
  final deepScore = 12 * rangeFactor(deepP, 0.13, 0.18);
  final remScore = 13 * _clamp01((remMin - 50) / 60); // 50..110 min
  final lightScore = 5 * rangeFactor(lightP, 0.45, 0.60, falloff: 0.25);
  final efficiencyScore = 10 * _clamp01((efficiency - 0.75) / 0.17);

  final raw = durationScore +
      deepScore +
      remScore +
      lightScore +
      efficiencyScore;
  return raw.round().clamp(0, 100);
}

/// Maps our raw score onto Samsung Health's scale. Fit by least-squares to four
/// nights of full stage data paired with their Samsung scores (22–25 Jun 2026).
/// Approximate: Samsung also uses signals Health Connect doesn't expose (sleep
/// latency, movement, snoring, regularity), so unusual nights can still differ
/// by a few points. Re-fit as more paired nights become available.
int calibrateSleepScore(int rawScore) {
  if (rawScore <= 0) return 0;
  const slope = 0.690;
  const intercept = 23.6;
  return (slope * rawScore + intercept).round().clamp(0, 100);
}

/// Points to subtract from a night's score for poor overnight vitals. Gentle
/// and penalty-only (good vitals never raise the score), and only triggers on
/// genuinely abnormal values so it doesn't fight the Samsung calibration on a
/// normal night.
///
/// [restingHr] is the minimum heart rate during sleep — the resting HR while
/// asleep. Thresholds are heuristic, not clinical.
int vitalsPenalty({double? spo2Avg, double? restingHr}) {
  var penalty = 0.0;
  if (spo2Avg != null && spo2Avg < 92) {
    penalty += ((92 - spo2Avg) * 2.5).clamp(0, 15); // up to -15
  }
  if (restingHr != null && restingHr > 62) {
    penalty += ((restingHr - 62) * 0.5).clamp(0, 10); // up to -10
  }
  return penalty.clamp(0, 20).round();
}

/// Aggregates raw stage segments into per-stage totals plus an ordered timeline.
SleepStageTotals aggregateStages(List<SleepStageSegment> segments) {
  var awake = 0, rem = 0, light = 0, deep = 0;
  for (final s in segments) {
    switch (s.stage) {
      case SleepStage.awake:
        awake += s.minutes;
      case SleepStage.rem:
        rem += s.minutes;
      case SleepStage.light:
        light += s.minutes;
      case SleepStage.deep:
        deep += s.minutes;
    }
  }
  final timeline = [...segments]..sort((a, b) => a.start.compareTo(b.start));
  return SleepStageTotals(
    awakeMinutes: awake,
    remMinutes: rem,
    lightMinutes: light,
    deepMinutes: deep,
    timeline: timeline,
  );
}
