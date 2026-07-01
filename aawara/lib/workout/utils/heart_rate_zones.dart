/// Heart-rate zone analysis for a workout's HR samples, using the standard
/// 5-zone model. Pure + unit-tested.
///
///   Zone 1  95–114 bpm — warm-up, easy walking
///   Zone 2 114–133 bpm — aerobic base, fat-burning, conversational pace
///   Zone 3 133–152 bpm — moderate, cardiovascular efficiency
///   Zone 4 152–171 bpm — hard, threshold / lactate tolerance
///   Zone 5 171–190 bpm — max effort, short bursts only
enum HrZone { zone1, zone2, zone3, zone4, zone5 }

/// Fixed BPM thresholds. Anything below 114 (incl. very low HR) is Zone 1.
HrZone zoneOf(num bpm) {
  if (bpm >= 171) return HrZone.zone5;
  if (bpm >= 152) return HrZone.zone4;
  if (bpm >= 133) return HrZone.zone3;
  if (bpm >= 114) return HrZone.zone2;
  return HrZone.zone1;
}

class HrSample {
  final DateTime t;
  final double hr;
  const HrSample(this.t, this.hr);
}

class HrZones {
  final int zone1Seconds;
  final int zone2Seconds;
  final int zone3Seconds;
  final int zone4Seconds;
  final int zone5Seconds;
  final double avg;
  final double max;
  final double min;

  const HrZones({
    required this.zone1Seconds,
    required this.zone2Seconds,
    required this.zone3Seconds,
    required this.zone4Seconds,
    required this.zone5Seconds,
    required this.avg,
    required this.max,
    required this.min,
  });

  int get totalSeconds =>
      zone1Seconds + zone2Seconds + zone3Seconds + zone4Seconds + zone5Seconds;
  bool get hasData => avg > 0;

  int secondsOf(HrZone z) => switch (z) {
        HrZone.zone1 => zone1Seconds,
        HrZone.zone2 => zone2Seconds,
        HrZone.zone3 => zone3Seconds,
        HrZone.zone4 => zone4Seconds,
        HrZone.zone5 => zone5Seconds,
      };
}

/// Attributes the time between each pair of samples to the earlier sample's
/// zone, and computes avg/max/min across all samples.
HrZones heartRateZones(List<HrSample> samples) {
  if (samples.isEmpty) {
    return const HrZones(
        zone1Seconds: 0,
        zone2Seconds: 0,
        zone3Seconds: 0,
        zone4Seconds: 0,
        zone5Seconds: 0,
        avg: 0,
        max: 0,
        min: 0);
  }
  final sorted = [...samples]..sort((a, b) => a.t.compareTo(b.t));
  var z1 = 0, z2 = 0, z3 = 0, z4 = 0, z5 = 0;
  for (var i = 0; i < sorted.length - 1; i++) {
    final dt = sorted[i + 1].t.difference(sorted[i].t).inSeconds;
    if (dt <= 0) continue;
    switch (zoneOf(sorted[i].hr)) {
      case HrZone.zone1:
        z1 += dt;
      case HrZone.zone2:
        z2 += dt;
      case HrZone.zone3:
        z3 += dt;
      case HrZone.zone4:
        z4 += dt;
      case HrZone.zone5:
        z5 += dt;
    }
  }
  var sum = 0.0, mx = sorted.first.hr, mn = sorted.first.hr;
  for (final s in sorted) {
    sum += s.hr;
    if (s.hr > mx) mx = s.hr;
    if (s.hr < mn) mn = s.hr;
  }
  return HrZones(
    zone1Seconds: z1,
    zone2Seconds: z2,
    zone3Seconds: z3,
    zone4Seconds: z4,
    zone5Seconds: z5,
    avg: sum / sorted.length,
    max: mx,
    min: mn,
  );
}
