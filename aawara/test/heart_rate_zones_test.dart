import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/heart_rate_zones.dart';

void main() {
  DateTime t(int minute) => DateTime(2026, 6, 19, 18, minute);

  group('heartRateZones', () {
    test('attributes inter-sample time to the sample zone', () {
      // one minute in each zone, in order warm→fat→cardio→peak
      final z = heartRateZones([
        HrSample(t(0), 100), // warm up
        HrSample(t(1), 130), // fat burn
        HrSample(t(2), 150), // cardio
        HrSample(t(3), 170), // peak
        HrSample(t(4), 170),
      ]);
      expect(z.warmUpSeconds, 60); // 0→1 at 100
      expect(z.fatBurnSeconds, 60); // 1→2 at 130
      expect(z.cardioSeconds, 60); // 2→3 at 150
      expect(z.peakSeconds, 60); // 3→4 at 170
    });

    test('computes avg/max/min', () {
      final z = heartRateZones([
        HrSample(t(0), 120),
        HrSample(t(1), 160),
        HrSample(t(2), 140),
      ]);
      expect(z.avg, closeTo(140, 0.1));
      expect(z.max, 160);
      expect(z.min, 120);
    });

    test('empty samples → all zero and hasData false', () {
      final z = heartRateZones([]);
      expect(z.hasData, isFalse);
      expect(z.totalSeconds, 0);
    });

    test('zone boundaries: 120 is fat burn, 140 cardio, 160 peak', () {
      expect(zoneOf(119), HrZone.warmUp);
      expect(zoneOf(120), HrZone.fatBurn);
      expect(zoneOf(139), HrZone.fatBurn);
      expect(zoneOf(140), HrZone.cardio);
      expect(zoneOf(159), HrZone.cardio);
      expect(zoneOf(160), HrZone.peak);
    });
  });
}
