import 'package:flutter/material.dart';

import '../database/workout_database.dart';
import '../utils/heart_rate_zones.dart';

/// Screen 3a: when a completed workout is linked to a watch (Samsung Health)
/// session that has heart-rate data, show a Heart Rate card (avg/max/min + zone
/// bar + time-in-zone) and energy stats above the exercise log. Renders nothing
/// when there's no linked session or no HR data — the screen stays as today.
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
  HrZone.warmUp: Color(0xFF3498DB),
  HrZone.fatBurn: Color(0xFF2ECC71),
  HrZone.cardio: Color(0xFFE67E22),
  HrZone.peak: Color(0xFFE74C3C),
};

class _WatchMetricsCardState extends State<WatchMetricsCard> {
  Map<String, dynamic>? _ex;
  HrZones? _zones;
  bool _loaded = false;

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

  Future<void> _load() async {
    final db = WorkoutDatabase.instance;
    final ex = await db.getSamsungExerciseForWorkout(widget.workoutId);
    HrZones? zones;
    if (ex != null) {
      final samples = await db.getSamsungExerciseSamples(ex['uid'] as String);
      if (samples.isNotEmpty) {
        zones = heartRateZones(
            [for (final s in samples) HrSample(s.t, s.hr)]);
      }
    }
    if (mounted) {
      setState(() {
        _ex = ex;
        _zones = zones;
        _loaded = true;
      });
    }
  }

  double? _num(String key) => (_ex?[key] as num?)?.toDouble();

  String _zoneTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ex == null) return const SizedBox.shrink();
    // HR present? (from the series or the session aggregate). If neither, keep
    // the screen as it is today.
    final avg = _zones?.avg ?? _num('mean_hr') ?? 0;
    if (avg <= 0) return const SizedBox.shrink();
    final max = _zones?.max ?? _num('max_hr') ?? avg;
    final min = _zones?.min ?? _num('min_hr') ?? avg;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          _heartRateCard(avg, max, min),
          const SizedBox(height: 12),
          _energyRow(),
        ],
      ),
    );
  }

  Widget _heartRateCard(double avg, double max, double min) {
    final z = _zones;
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
              const Text('Heart Rate',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              _samsungChip(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${avg.round()}',
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
              _minMax('MAX', max.round(), _red),
              const SizedBox(width: 16),
              _minMax('MIN', min.round(), const Color(0xFF3498DB)),
            ],
          ),
          if (z != null && z.totalSeconds > 0) ...[
            const SizedBox(height: 16),
            _zoneBar(z),
            const SizedBox(height: 14),
            _zoneRow(HrZone.peak, 'Peak', '160+ bpm', z),
            _zoneRow(HrZone.cardio, 'Cardio', '140–159 bpm', z),
            _zoneRow(HrZone.fatBurn, 'Fat burn', '120–139 bpm', z),
            _zoneRow(HrZone.warmUp, 'Warm up', '< 120 bpm', z),
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
          border: Border.all(color: const Color(0xFF3896EB).withValues(alpha: 0.35)),
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
                  color: color, fontSize: 19, fontWeight: FontWeight.bold, height: 1)),
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
          seg(HrZone.warmUp),
          seg(HrZone.fatBurn),
          seg(HrZone.cardio),
          seg(HrZone.peak),
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

  Widget _energyRow() {
    final cal = _num('calories')?.round();
    final dist = _num('distance');
    final items = <Widget>[];
    if (cal != null && cal > 0) {
      items.add(_energyStat(Icons.local_fire_department_rounded, '$cal', 'kcal',
          'Active energy', const Color(0xFFE67E22)));
    }
    if (dist != null && dist > 0) {
      items.add(_energyStat(Icons.straighten_rounded,
          (dist / 1000).toStringAsFixed(2), 'km', 'Distance',
          const Color(0xFF3498DB)));
    }
    final vo2 = _num('vo2max')?.round();
    if (vo2 != null && vo2 > 0) {
      items.add(_energyStat(
          Icons.air_rounded, '$vo2', '', 'VO₂max', const Color(0xFF1ABC9C)));
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
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
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
