import 'heart_rate_zones.dart';
import 'sleep_series.dart';

/// Turns raw watch HR samples into chart points, dropping non-positive readings
/// (Samsung emits 0/-1 for dropouts). Samples are assumed already time-ordered.
List<SeriesPoint> hrSeriesPoints(List<HrSample> samples) => [
      for (final s in samples)
        if (s.hr > 0) SeriesPoint(s.t, s.hr),
    ];
