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

// Healthy adult stage proportions (fraction of time asleep). Full marks when a
// stage lands inside its range; points fall off as it strays above or below.
const _deepRange = (low: 0.14, high: 0.24);
const _remRange = (low: 0.20, high: 0.25);

/// 1.0 when [value] is within [low, high], falling linearly to 0 as it moves
/// [falloff] beyond either bound (default: the [low] bound's width).
double rangeFactor(double value, double low, double high, {double? falloff}) {
  if (value >= low && value <= high) return 1.0;
  final f = falloff ?? low;
  if (f <= 0) return 0.0;
  final dist = value < low ? low - value : value - high;
  return (1 - dist / f).clamp(0.0, 1.0);
}

/// Our own transparent 0–100 sleep score (Samsung's score is not in Health
/// Connect). Components: duration (50), deep within healthy range (20), REM
/// within healthy range (20), efficiency / low-awake (10). Stage components use
/// a range — too little OR too much of a stage cuts the score. Returns 0 for an
/// empty night.
int computeSleepScore({
  required int asleep,
  required int deep,
  required int rem,
  required int awake,
  required int total,
}) {
  if (asleep <= 0 || total <= 0) return 0;

  double cap(double v) => v > 1.0 ? 1.0 : v;

  final duration = 50 * cap(asleep / 450); // ~7.5h target
  final deepScore =
      20 * rangeFactor(deep / asleep, _deepRange.low, _deepRange.high);
  final remScore =
      20 * rangeFactor(rem / asleep, _remRange.low, _remRange.high);
  final efficiency = 10 * cap(asleep / total);

  final score = (duration + deepScore + remScore + efficiency).round();
  return score.clamp(0, 100);
}

/// Maps our raw score onto Samsung Health's scale. Fit by least-squares to 7
/// nights of paired (ours, Samsung) scores — our formula consistently ran a few
/// points hot, so this scales it down and shifts it. Approximate: Samsung also
/// uses signals Health Connect doesn't expose (movement, snoring, regularity),
/// so unusual nights can still differ by several points.
int calibrateSleepScore(int rawScore) {
  if (rawScore <= 0) return 0;
  const slope = 0.863;
  const intercept = 6.9;
  return (slope * rawScore + intercept).round().clamp(0, 100);
}

/// Points to subtract from a night's score for poor overnight vitals. Gentle
/// and penalty-only (good vitals never raise the score), so it leaves the
/// Samsung-calibrated stage score untouched on a normal night and only docks
/// points when blood oxygen dips or the resting heart rate runs high.
///
/// [restingHr] is the minimum heart rate during sleep — the resting HR while
/// asleep. Thresholds are heuristic, not clinical.
int vitalsPenalty({double? spo2Avg, double? restingHr}) {
  var penalty = 0.0;
  if (spo2Avg != null && spo2Avg < 95) {
    penalty += ((95 - spo2Avg) * 2).clamp(0, 15); // up to -15
  }
  if (restingHr != null && restingHr > 58) {
    penalty += ((restingHr - 58) * 0.5).clamp(0, 10); // up to -10
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
