/// Heart-rate zone analysis for a workout's HR samples, matching the "View
/// Workout" design (Warm-up / Fat-burn / Cardio / Peak). Pure + unit-tested.

enum HrZone { warmUp, fatBurn, cardio, peak }

/// Fixed BPM thresholds (design 3a): <120 warm-up, 120–139 fat-burn,
/// 140–159 cardio, ≥160 peak.
HrZone zoneOf(num bpm) {
  if (bpm >= 160) return HrZone.peak;
  if (bpm >= 140) return HrZone.cardio;
  if (bpm >= 120) return HrZone.fatBurn;
  return HrZone.warmUp;
}

class HrSample {
  final DateTime t;
  final double hr;
  const HrSample(this.t, this.hr);
}

class HrZones {
  final int warmUpSeconds;
  final int fatBurnSeconds;
  final int cardioSeconds;
  final int peakSeconds;
  final double avg;
  final double max;
  final double min;

  const HrZones({
    required this.warmUpSeconds,
    required this.fatBurnSeconds,
    required this.cardioSeconds,
    required this.peakSeconds,
    required this.avg,
    required this.max,
    required this.min,
  });

  int get totalSeconds =>
      warmUpSeconds + fatBurnSeconds + cardioSeconds + peakSeconds;
  bool get hasData => avg > 0;

  int secondsOf(HrZone z) => switch (z) {
        HrZone.warmUp => warmUpSeconds,
        HrZone.fatBurn => fatBurnSeconds,
        HrZone.cardio => cardioSeconds,
        HrZone.peak => peakSeconds,
      };
}

/// Attributes the time between each pair of samples to the earlier sample's
/// zone, and computes avg/max/min across all samples.
HrZones heartRateZones(List<HrSample> samples) {
  if (samples.isEmpty) {
    return const HrZones(
        warmUpSeconds: 0,
        fatBurnSeconds: 0,
        cardioSeconds: 0,
        peakSeconds: 0,
        avg: 0,
        max: 0,
        min: 0);
  }
  final sorted = [...samples]..sort((a, b) => a.t.compareTo(b.t));
  var warm = 0, fat = 0, cardio = 0, peak = 0;
  for (var i = 0; i < sorted.length - 1; i++) {
    final dt = sorted[i + 1].t.difference(sorted[i].t).inSeconds;
    if (dt <= 0) continue;
    switch (zoneOf(sorted[i].hr)) {
      case HrZone.warmUp:
        warm += dt;
      case HrZone.fatBurn:
        fat += dt;
      case HrZone.cardio:
        cardio += dt;
      case HrZone.peak:
        peak += dt;
    }
  }
  var sum = 0.0, mx = sorted.first.hr, mn = sorted.first.hr;
  for (final s in sorted) {
    sum += s.hr;
    if (s.hr > mx) mx = s.hr;
    if (s.hr < mn) mn = s.hr;
  }
  return HrZones(
    warmUpSeconds: warm,
    fatBurnSeconds: fat,
    cardioSeconds: cardio,
    peakSeconds: peak,
    avg: sum / sorted.length,
    max: mx,
    min: mn,
  );
}
