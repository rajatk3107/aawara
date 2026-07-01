import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/heart_rate_zones.dart';

void main() {
  DateTime t(int minute) => DateTime(2026, 6, 19, 18, minute);

  group('heartRateZones (5-zone model)', () {
    test('attributes inter-sample time to the sample zone', () {
      // one minute in each zone, in order zone1→zone5
      final z = heartRateZones([
        HrSample(t(0), 100), // zone 1  (< 114)
        HrSample(t(1), 120), // zone 2  (114–133)
        HrSample(t(2), 140), // zone 3  (133–152)
        HrSample(t(3), 160), // zone 4  (152–171)
        HrSample(t(4), 180), // zone 5  (≥ 171)
        HrSample(t(5), 180),
      ]);
      expect(z.secondsOf(HrZone.zone1), 60); // 0→1 at 100
      expect(z.secondsOf(HrZone.zone2), 60); // 1→2 at 120
      expect(z.secondsOf(HrZone.zone3), 60); // 2→3 at 140
      expect(z.secondsOf(HrZone.zone4), 60); // 3→4 at 160
      expect(z.secondsOf(HrZone.zone5), 60); // 4→5 at 180
      expect(z.totalSeconds, 300);
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

    test('zone boundaries: 114 z2, 133 z3, 152 z4, 171 z5', () {
      expect(zoneOf(95), HrZone.zone1);
      expect(zoneOf(113), HrZone.zone1);
      expect(zoneOf(114), HrZone.zone2);
      expect(zoneOf(132), HrZone.zone2);
      expect(zoneOf(133), HrZone.zone3);
      expect(zoneOf(151), HrZone.zone3);
      expect(zoneOf(152), HrZone.zone4);
      expect(zoneOf(170), HrZone.zone4);
      expect(zoneOf(171), HrZone.zone5);
      expect(zoneOf(190), HrZone.zone5);
    });

    test('very low HR (below 95) still counts as zone 1', () {
      expect(zoneOf(70), HrZone.zone1);
    });
  });
}
