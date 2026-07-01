import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/heart_rate_zones.dart';
import 'package:aawara/workout/utils/sleep_series.dart';
import 'package:aawara/workout/utils/watch_hr_series.dart';

DateTime _t(int s) => DateTime(2026, 1, 1, 10, 0, s);

void main() {
  group('hrSeriesPoints', () {
    test('maps samples to time/value points', () {
      final pts = hrSeriesPoints([HrSample(_t(0), 90), HrSample(_t(10), 120)]);
      expect(pts.length, 2);
      expect(pts.first.t, _t(0));
      expect(pts.first.v, 90);
      expect(pts.last.v, 120);
    });

    test('drops non-positive heart rates (dropouts/gaps)', () {
      final pts = hrSeriesPoints(
          [HrSample(_t(0), 0), HrSample(_t(10), 118), HrSample(_t(20), -1)]);
      expect(pts.map((p) => p.v), [118]);
    });

    test('empty in, empty out', () {
      expect(hrSeriesPoints(const []), isEmpty);
    });
  });

  group('downsampleSeries', () {
    test('keeps series unchanged when already under the cap', () {
      final pts = hrSeriesPoints(
          [for (var i = 0; i < 5; i++) HrSample(_t(i * 10), 100.0 + i)]);
      expect(downsampleSeries(pts, 180).length, 5);
    });

    test('reduces to at most the cap while keeping first and last', () {
      final pts = hrSeriesPoints(
          [for (var i = 0; i < 1000; i++) HrSample(_t(i), 100.0 + (i % 40))]);
      final ds = downsampleSeries(pts, 180);
      expect(ds.length, lessThanOrEqualTo(180));
      expect(ds.first.t, pts.first.t);
      expect(ds.last.t, pts.last.t);
    });
  });
}
