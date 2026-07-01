import 'package:flutter/material.dart';

import '../database/workout_database.dart';
import '../utils/heart_rate_zones.dart';
import '../utils/sleep_series.dart';
import '../utils/watch_hr_series.dart';
import 'workout_hr_chart.dart';

/// Screen 3a: for a completed workout, show the watch (Samsung Health) sessions
/// that belong to it — each as a Heart Rate card (avg/max/min + zone bar +
/// time-in-zone) plus energy. Multiple sessions (e.g. weights + treadmill) are
/// shown as a swipeable carousel. Renders nothing when there's no watch data
/// with heart rate — the screen stays as today.
class WatchMetricsCard extends StatefulWidget {
  final String workoutId;
  const WatchMetricsCard({super.key, required this.workoutId});

  @override
  State<WatchMetricsCard> createState() => _WatchMetricsCardState();
}

const _card = Color(0xFF1A1A2E);
const _border = Color(0xFF1E1E35);
const _muted = Color(0xFF888899);
const _red = Color(0xFFE74C3C);

const _zoneColors = {
  HrZone.zone1: Color(0xFF3498DB), // warm-up
  HrZone.zone2: Color(0xFF2ECC71), // aerobic
  HrZone.zone3: Color(0xFFF1C40F), // moderate
  HrZone.zone4: Color(0xFFE67E22), // threshold
  HrZone.zone5: Color(0xFFE74C3C), // max
};

class _WatchSession {
  final Map<String, dynamic> row;
  final HrZones? zones;
  final List<SeriesPoint> series; // per-sample HR for the line chart
  const _WatchSession(this.row, this.zones, this.series);

  double get avg => zones?.avg ?? (row['mean_hr'] as num?)?.toDouble() ?? 0;
  double get max => zones?.max ?? (row['max_hr'] as num?)?.toDouble() ?? avg;
  double get min => zones?.min ?? (row['min_hr'] as num?)?.toDouble() ?? avg;
  bool get hasHr => avg > 0;
  bool get hasZones => zones != null && zones!.totalSeconds > 0;
  bool get hasChart => series.length >= 2;
}

class _WatchMetricsCardState extends State<WatchMetricsCard> {
  List<_WatchSession> _sessions = const [];
  bool _loaded = false;
  final _pageCtrl = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WatchMetricsCard old) {
    super.didUpdateWidget(old);
    if (old.workoutId != widget.workoutId) _load();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = WorkoutDatabase.instance;
    final rows = await db.getWatchSessionsForWorkout(widget.workoutId);
    final sessions = <_WatchSession>[];
    for (final r in rows) {
      final samples = await db.getSamsungExerciseSamples(r['uid'] as String);
      final hrSamples = [for (final s in samples) HrSample(s.t, s.hr)];
      final z = hrSamples.isEmpty ? null : heartRateZones(hrSamples);
      final series = downsampleSeries(hrSeriesPoints(hrSamples), 180);
      final s = _WatchSession(r, z, series);
      if (s.hasHr) sessions.add(s); // only sessions with HR data
    }
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loaded = true;
      });
    }
  }

  static String _title(Map<String, dynamic> r) {
    final t = (r['custom_title'] as String?) ?? (r['exercise_type'] as String?);
    if (t == null) return 'Watch workout';
    return t
        .split('_')
        .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }

  String _zoneTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _sessions.isEmpty) return const SizedBox.shrink();
    final hasZones = _sessions.any((s) => s.hasZones);
    final hasChart = _sessions.any((s) => s.hasChart);
    final multi = _sessions.length > 1;
    final height = (hasZones ? 486.0 : 272.0) + (hasChart ? 158.0 : 0.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (multi)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.watch_rounded, color: _muted, size: 13),
                  const SizedBox(width: 6),
                  Text('FROM WATCH · ${_sessions.length} SESSIONS',
                      style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                  const Spacer(),
                  const Text('swipe →',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),
          SizedBox(
            height: height,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _sessions.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: multi ? 4 : 0),
                child: _sessionPage(_sessions[i]),
              ),
            ),
          ),
          if (multi)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _sessions.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF333355),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionPage(_WatchSession s) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          _heartRateCard(s),
          const SizedBox(height: 12),
          _energyRow(s.row),
        ],
      ),
    );
  }

  Widget _heartRateCard(_WatchSession s) {
    final z = s.zones;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: _red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Heart Rate · ${_title(s.row)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
              _samsungChip(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${s.avg.round()}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      height: 0.9)),
              const Padding(
                padding: EdgeInsets.only(left: 5, bottom: 5),
                child: Text('avg bpm',
                    style: TextStyle(color: _muted, fontSize: 13)),
              ),
              const Spacer(),
              _minMax('MAX', s.max.round(), _red),
              const SizedBox(width: 16),
              _minMax('MIN', s.min.round(), const Color(0xFF3498DB)),
            ],
          ),
          if (s.hasChart) ...[
            const SizedBox(height: 18),
            WorkoutHrChart(points: s.series, average: s.avg),
          ],
          if (z != null && z.totalSeconds > 0) ...[
            const SizedBox(height: 16),
            _zoneBar(z),
            const SizedBox(height: 14),
            _zoneRow(HrZone.zone5, 'Zone 5', 'Max · 171–190', z),
            _zoneRow(HrZone.zone4, 'Zone 4', 'Threshold · 152–171', z),
            _zoneRow(HrZone.zone3, 'Zone 3', 'Moderate · 133–152', z),
            _zoneRow(HrZone.zone2, 'Zone 2', 'Aerobic · 114–133', z),
            _zoneRow(HrZone.zone1, 'Zone 1', 'Warm-up · 95–114', z),
          ],
        ],
      ),
    );
  }

  Widget _samsungChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF146DCA).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: const Color(0xFF3896EB).withValues(alpha: 0.35)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.watch_rounded, color: Color(0xFF8FC2F5), size: 11),
          SizedBox(width: 5),
          Text('Samsung Health',
              style: TextStyle(color: Color(0xFF8FC2F5), fontSize: 11)),
        ]),
      );

  Widget _minMax(String label, int value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$value',
              style: TextStyle(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  height: 1)),
          Text(label,
              style: const TextStyle(
                  color: _muted, fontSize: 10, letterSpacing: 0.5)),
        ],
      );

  Widget _zoneBar(HrZones z) {
    Widget seg(HrZone zone) {
      final secs = z.secondsOf(zone);
      if (secs == 0) return const SizedBox.shrink();
      return Expanded(flex: secs, child: Container(color: _zoneColors[zone]));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 9,
        child: Row(children: [
          seg(HrZone.zone1),
          seg(HrZone.zone2),
          seg(HrZone.zone3),
          seg(HrZone.zone4),
          seg(HrZone.zone5),
        ]),
      ),
    );
  }

  Widget _zoneRow(HrZone zone, String label, String range, HrZones z) {
    final secs = z.secondsOf(zone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: _zoneColors[zone],
                borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFFCDD3E0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          Text(range, style: const TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(_zoneTime(secs),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _energyRow(Map<String, dynamic> row) {
    double? n(String k) => (row[k] as num?)?.toDouble();
    final items = <Widget>[];
    final cal = n('calories')?.round();
    if (cal != null && cal > 0) {
      items.add(_energyStat(Icons.local_fire_department_rounded, '$cal', 'kcal',
          'Active energy', const Color(0xFFE67E22)));
    }
    final dur = row['duration_seconds'] as int?;
    if (dur != null && dur > 0) {
      final m = dur ~/ 60;
      items.add(_energyStat(Icons.timer_outlined,
          m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m', '', 'Duration',
          const Color(0xFFFFD700)));
    }
    final dist = n('distance');
    if (dist != null && dist > 0) {
      items.add(_energyStat(Icons.straighten_rounded,
          (dist / 1000).toStringAsFixed(2), 'km', 'Distance',
          const Color(0xFF3498DB)));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: items[i]),
        ],
      ],
    );
  }

  Widget _energyStat(
      IconData icon, String value, String unit, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              if (unit.isNotEmpty)
                Text(' $unit',
                    style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}
