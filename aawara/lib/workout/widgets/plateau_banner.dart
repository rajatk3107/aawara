import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plateau_alert.dart';
import '../screens/exercise_progress_detail_screen.dart';
import '../database/workout_database.dart';

class PlateauBanner extends StatefulWidget {
  const PlateauBanner({super.key});

  @override
  State<PlateauBanner> createState() => _PlateauBannerState();
}

class _PlateauBannerState extends State<PlateauBanner> {
  List<PlateauAlert> _visible = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await WorkoutDatabase.instance.getPlateauedExercises();
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    final visible = <PlateauAlert>[];
    for (final alert in all) {
      final key = 'plateau_dismissed_${alert.exerciseId}';
      final dismissedMs = prefs.getInt(key);
      if (dismissedMs != null) {
        final dismissedAt = DateTime.fromMillisecondsSinceEpoch(dismissedMs);
        if (now.difference(dismissedAt).inDays < 7) continue; // still suppressed
        await prefs.remove(key); // 7 days passed — clear so it re-shows
      }
      visible.add(alert);
    }

    if (mounted) setState(() { _visible = visible; _loaded = true; });
  }

  Future<void> _dismiss(PlateauAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'plateau_dismissed_${alert.exerciseId}',
      DateTime.now().millisecondsSinceEpoch,
    );
    if (mounted) setState(() => _visible.remove(alert));
  }

  Future<void> _dismissAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final a in _visible) {
      await prefs.setInt(
        'plateau_dismissed_${a.exerciseId}',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (mounted) setState(() => _visible.clear());
  }

  Future<void> _openDetail(PlateauAlert alert) async {
    final ex = await WorkoutDatabase.instance.getExerciseById(alert.exerciseId);
    if (!mounted || ex == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseProgressDetailScreen(exercise: ex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _visible.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: const BorderSide(color: Color(0xFFEF9F27), width: 3.5),
          top: BorderSide(color: const Color(0xFFEF9F27).withValues(alpha: 0.15)),
          right: BorderSide(color: const Color(0xFFEF9F27).withValues(alpha: 0.15)),
          bottom: BorderSide(color: const Color(0xFFEF9F27).withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
            child: Row(
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plateau detected on ${_visible.length} exercise${_visible.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Color(0xFFEF9F27),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _dismissAll,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      'Dismiss',
                      style: TextStyle(
                        color: Color(0xFF555577),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1E1E35), height: 1, indent: 14),
          // Alert rows
          ...List.generate(_visible.length, (i) {
            final alert = _visible[i];
            return _AlertRow(
              alert: alert,
              isLast: i == _visible.length - 1,
              onTap: () => _openDetail(alert),
              onDismiss: () => _dismiss(alert),
            );
          }),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final PlateauAlert alert;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _AlertRow({
    required this.alert,
    required this.isLast,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              alert.exerciseName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF9F27).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${alert.weeksStagnant}w',
                              style: const TextStyle(
                                color: Color(0xFFEF9F27),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alert.suggestion,
                        style: const TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF444466),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(color: Color(0xFF1E1E35), height: 1, indent: 14),
      ],
    );
  }
}
