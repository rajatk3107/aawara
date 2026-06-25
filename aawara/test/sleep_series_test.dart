import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/sleep_series.dart';

void main() {
  group('sleep series encode/decode', () {
    test('round-trips points', () {
      final pts = [
        SeriesPoint(DateTime(2026, 6, 24, 22, 40), 64),
        SeriesPoint(DateTime(2026, 6, 24, 23, 10), 58.5),
      ];
      final decoded = decodeSeries(encodeSeries(pts));
      expect(decoded.length, 2);
      expect(decoded[0].v, 64);
      expect(decoded[0].t, DateTime(2026, 6, 24, 22, 40));
      expect(decoded[1].v, 58.5);
    });

    test('decodes null/empty to an empty list', () {
      expect(decodeSeries(null), isEmpty);
      expect(decodeSeries(''), isEmpty);
      expect(decodeSeries('garbage'), isEmpty);
    });

    test('downsamples to at most maxPoints, keeping first and last', () {
      final pts = List.generate(
          1000, (i) => SeriesPoint(DateTime(2026, 6, 24).add(Duration(minutes: i)), i.toDouble()));
      final reduced = downsampleSeries(pts, 100);
      expect(reduced.length, lessThanOrEqualTo(100));
      expect(reduced.first.v, 0);
      expect(reduced.last.v, 999);
    });

    test('downsample leaves small series untouched', () {
      final pts = [
        SeriesPoint(DateTime(2026, 6, 24, 1), 1),
        SeriesPoint(DateTime(2026, 6, 24, 2), 2),
      ];
      expect(downsampleSeries(pts, 100).length, 2);
    });
  });
}
