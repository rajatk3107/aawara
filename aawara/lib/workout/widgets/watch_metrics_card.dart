import 'package:flutter/material.dart';

import '../database/workout_database.dart';

/// Shows the watch (Samsung Health) metrics linked to a logged workout, so the
/// user sees HR/calories/distance alongside their sets & reps. Renders nothing
/// when the workout isn't linked to a watch session.
class WatchMetricsCard extends StatefulWidget {
  final String workoutId;
  const WatchMetricsCard({super.key, required this.workoutId});

  @override
  State<WatchMetricsCard> createState() => _WatchMetricsCardState();
}

class _WatchMetricsCardState extends State<WatchMetricsCard> {
  Map<String, dynamic>? _ex;
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
    final ex = await WorkoutDatabase.instance
        .getSamsungExerciseForWorkout(widget.workoutId);
    if (mounted) {
      setState(() {
        _ex = ex;
        _loaded = true;
      });
    }
  }

  String _dur(int? sec) {
    if (sec == null || sec == 0) return '–';
    final m = sec ~/ 60;
    final h = m ~/ 60;
    return h == 0 ? '${m}m' : '${h}h ${m % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ex == null) return const SizedBox.shrink();
    final e = _ex!;
    final chips = <Widget>[];
    void add(IconData i, String v, String l, Color c) {
      chips.add(_metric(i, v, l, c));
    }

    final cal = (e['calories'] as num?)?.round();
    if (cal != null && cal > 0) {
      add(Icons.local_fire_department_rounded, '$cal', 'kcal',
          const Color(0xFFE67E22));
    }
    add(Icons.timer_outlined, _dur(e['duration_seconds'] as int?), 'duration',
        const Color(0xFFFFD700));
    final meanHr = (e['mean_hr'] as num?)?.round();
    if (meanHr != null) {
      final maxHr = (e['max_hr'] as num?)?.round();
      add(Icons.favorite_rounded, '$meanHr',
          maxHr != null ? 'avg · $maxHr max' : 'avg bpm',
          const Color(0xFFE74C3C));
    }
    final dist = (e['distance'] as num?)?.toDouble();
    if (dist != null && dist > 0) {
      add(Icons.straighten_rounded, (dist / 1000).toStringAsFixed(2), 'km',
          const Color(0xFF3498DB));
    }
    final vo2 = (e['vo2max'] as num?)?.round();
    if (vo2 != null && vo2 > 0) {
      add(Icons.air_rounded, '$vo2', 'VO₂max', const Color(0xFF1ABC9C));
    }

    final title = (e['custom_title'] as String?) ??
        (e['exercise_type'] as String?)?.replaceAll('_', ' ').toLowerCase() ??
        'Watch workout';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_rounded,
                  color: Color(0xFF888899), size: 14),
              const SizedBox(width: 6),
              Text('FROM WATCH · ${title.toUpperCase()}',
                  style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 12, children: chips),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(color: Color(0xFF888899), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
