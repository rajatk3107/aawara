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

/// Our own transparent 0–100 sleep score (Samsung's score is not in Health
/// Connect). Components: duration (50), deep proportion (20), REM proportion
/// (20), efficiency / low-awake (10). Returns 0 for an empty night.
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
  final deepScore = 20 * cap((deep / asleep) / 0.18); // ~18% target
  final remScore = 20 * cap((rem / asleep) / 0.22); // ~22% target
  final efficiency = 10 * cap(asleep / total);

  final score = (duration + deepScore + remScore + efficiency).round();
  return score.clamp(0, 100);
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
