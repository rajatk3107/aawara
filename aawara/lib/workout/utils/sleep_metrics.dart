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

// ─── Sleep score (Samsung-calibrated, per sleep_score_spec.md) ───────────────
// Weighted feature scoring: each metric → 0..1 via a lookup, × weight, summed,
// then a linear calibration to Samsung's scale (clamped 50..100). Calibrated to
// 7 nights of Samsung Health data (19–25 Jun 2026), MAE ~0.4 pts.

/// Minutes after 9:00 PM for [bedtime] (sleep start), wrapping past midnight.
int bedtimeOffset(DateTime bedtime) {
  const anchor = 21 * 60; // 9:00 PM
  var bedtimeMinutes = bedtime.hour * 60 + bedtime.minute;
  if (bedtimeMinutes < 12 * 60) bedtimeMinutes += 24 * 60; // past midnight
  return bedtimeMinutes - anchor;
}

double _clamp01(double v) => v.clamp(0.0, 1.0);

double scoreDuration(double m) {
  if (m >= 420 && m <= 540) return 1.0; // 7–9h
  if (m >= 390 && m < 420) return 0.5 + 0.5 * (m - 390) / 30;
  if (m > 540 && m <= 570) return 1.0 - 0.5 * (m - 540) / 30;
  if (m >= 330 && m < 390) return 0.2 + 0.3 * (m - 330) / 60;
  return _clamp01(m / 420 * 0.3);
}

double scoreDeep(double m) {
  if (m >= 90) return 1.0;
  if (m >= 60) return 0.8 + 0.2 * (m - 60) / 30;
  if (m >= 40) return 0.55 + 0.25 * (m - 40) / 20;
  if (m >= 20) return 0.3 + 0.25 * (m - 20) / 20;
  return _clamp01(m / 20 * 0.3);
}

double scoreRem(double m) {
  if (m >= 120) return 1.0;
  if (m >= 90) return 0.8 + 0.2 * (m - 90) / 30;
  if (m >= 60) return 0.5 + 0.3 * (m - 60) / 30;
  if (m >= 30) return 0.2 + 0.3 * (m - 30) / 30;
  return _clamp01(m / 30 * 0.2);
}

double scoreAwake(double m) {
  if (m <= 20) return 1.0;
  if (m <= 40) return 0.85 - 0.15 * (m - 20) / 20;
  if (m <= 60) return 0.70 - 0.20 * (m - 40) / 20;
  return _clamp01(0.50 - 0.50 * (m - 60) / 60);
}

/// Samsung penalizes both extremes — optimal latency is 8–20 min.
double scoreLatency(double m) {
  if (m >= 8 && m <= 20) return 1.0;
  if (m > 20 && m <= 30) return 0.85;
  if (m > 30 && m <= 45) return 0.70;
  if (m > 45) return (1.0 - m / 60).clamp(0.3, 0.7);
  if (m >= 3) return 0.75; // fell asleep fast
  return 0.60; // <3 min — Samsung flags as "Attention"
}

/// Bedtime timing — the dominant factor. [offset] = minutes after 9 PM.
double scoreBedtime(int offset) {
  if (offset >= 55 && offset <= 90) return 1.0; // 9:55–10:30 PM
  if (offset > 90 && offset <= 105) return 0.85;
  if (offset > 105 && offset <= 120) return 0.65;
  if (offset > 120) return (1.0 - (offset - 90) / 130.0).clamp(0.2, 0.65);
  if (offset >= 30) return 0.85; // 9:30–9:55 PM
  return 0.65; // before 9:30 PM
}

/// SpO₂ dip ([m] = minutes below 90%). Deliberately low weight — Samsung barely
/// reflects it in the score. Surface dips as a separate health warning in the UI.
double scoreSpo2(double m) {
  if (m <= 2) return 1.0;
  if (m <= 5) return 0.97;
  if (m <= 10) return 0.93;
  if (m <= 20) return 0.88;
  return 0.82;
}

double scoreHr(int bpm) {
  if (bpm >= 58 && bpm <= 65) return 1.0;
  if (bpm > 65 && bpm <= 70) return 0.85;
  if (bpm > 70 && bpm <= 75) return 0.65;
  if (bpm >= 50 && bpm < 58) return 0.90;
  return 0.50;
}

/// Feature weights (sum to 100). Bedtime and duration dominate.
const _wBedtime = 26;
const _wDuration = 22;
const _wRem = 17;
const _wLatency = 13;
const _wDeep = 12;
const _wAwake = 4;
const _wHr = 4;
const _wSpo2 = 2;

/// Final 0–100 sleep score (clamped 50–100), per the calibrated spec.
int computeSleepScore({
  required double actualSleepMinutes,
  required double deepSleepMinutes,
  required double remSleepMinutes,
  required double awakeMinutes,
  required double latencyMinutes,
  required DateTime bedtime,
  required int avgHrBpm,
  required double spo2DipMinutes,
}) {
  if (actualSleepMinutes <= 0) return 0;
  final offset = bedtimeOffset(bedtime);

  final raw = scoreDuration(actualSleepMinutes) * _wDuration +
      scoreDeep(deepSleepMinutes) * _wDeep +
      scoreRem(remSleepMinutes) * _wRem +
      scoreAwake(awakeMinutes) * _wAwake +
      scoreLatency(latencyMinutes) * _wLatency +
      scoreBedtime(offset) * _wBedtime +
      scoreSpo2(spo2DipMinutes) * _wSpo2 +
      scoreHr(avgHrBpm) * _wHr;

  final calibrated = 63.1 * (raw / 100.0) + 29.7;
  return calibrated.round().clamp(50, 100);
}

/// Overall label, matching Samsung's bands.
String sleepScoreLabel(int score) {
  if (score >= 90) return 'Excellent';
  if (score >= 80) return 'Good';
  if (score >= 70) return 'Fair';
  return 'Needs attention';
}

/// Per-factor label from a 0..1 feature score (for the breakdown cards).
String factorLabel(double featureScore) {
  if (featureScore >= 0.95) return 'Excellent';
  if (featureScore >= 0.80) return 'Good';
  if (featureScore >= 0.60) return 'Fair';
  return 'Attention';
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
