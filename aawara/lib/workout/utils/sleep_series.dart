import 'dart:convert';

/// A timestamped sample (heart rate or SpO₂) within a sleep window, used to draw
/// the overnight line charts.
class SeriesPoint {
  final DateTime t;
  final double v;
  const SeriesPoint(this.t, this.v);
}

/// Encodes points as a compact JSON list of `{t: iso, v: value}`.
String encodeSeries(List<SeriesPoint> points) => jsonEncode([
      for (final p in points) {'t': p.t.toIso8601String(), 'v': p.v},
    ]);

/// Decodes [encodeSeries] output. Returns an empty list for null/blank/invalid.
List<SeriesPoint> decodeSeries(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list)
        SeriesPoint(
          DateTime.parse(e['t'] as String),
          (e['v'] as num).toDouble(),
        )
    ];
  } catch (_) {
    return const [];
  }
}

/// Caps a series to at most [maxPoints] by uniform stride, always keeping the
/// first and last samples so the chart spans the full night.
List<SeriesPoint> downsampleSeries(List<SeriesPoint> points, int maxPoints) {
  if (maxPoints < 2 || points.length <= maxPoints) return points;
  final stride = (points.length / maxPoints).ceil();
  final out = <SeriesPoint>[];
  for (var i = 0; i < points.length; i += stride) {
    out.add(points[i]);
  }
  // Keep the true last sample without growing past maxPoints.
  out[out.length - 1] = points.last;
  return out;
}
