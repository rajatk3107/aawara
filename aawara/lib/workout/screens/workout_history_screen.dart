import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/workout_database.dart';
import '../models/workout_log.dart';
import 'export_screen.dart';
import 'workout_logging_screen.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  final _db = WorkoutDatabase.instance;
  List<WorkoutLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await _db.getAllWorkoutLogs();
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  // Groups logs by month label
  Map<String, List<WorkoutLog>> get _grouped {
    final map = <String, List<WorkoutLog>>{};
    for (final log in _logs) {
      try {
        final d = DateTime.parse(log.date);
        final key = DateFormat('MMMM yyyy').format(d);
        map.putIfAbsent(key, () => []).add(log);
      } catch (_) {
        map.putIfAbsent('Unknown', () => []).add(log);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final months = grouped.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Workout History',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Export Data',
            icon: const Icon(Icons.ios_share_rounded, color: Color(0xFFFFD700)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExportScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _logs.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFFFFD700),
                  backgroundColor: const Color(0xFF1A1A2E),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: months.length,
                    itemBuilder: (_, mi) {
                      final month = months[mi];
                      final monthLogs = grouped[month]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              month.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF888899),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          ...monthLogs.map((log) => _LogCard(
                                log: log,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          WorkoutLoggingScreen(workoutLog: log),
                                    ),
                                  );
                                  _load();
                                },
                              )),
                        ],
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, color: Color(0xFF333355), size: 64),
          SizedBox(height: 16),
          Text('No workouts yet',
              style: TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Complete your first workout to\nsee it here!',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Color(0xFF555566), fontSize: 13)),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final WorkoutLog log;
  final VoidCallback onTap;

  const _LogCard({required this.log, required this.onTap});

  String get _dayLabel {
    try {
      final d = DateTime.parse(log.date);
      return DateFormat('EEE, MMM d').format(d);
    } catch (_) {
      return log.date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSets = log.totalSets;
    final volume = log.totalVolume;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: log.completed
                ? const Color(0xFF2ECC71).withOpacity(0.2)
                : const Color(0xFF333355),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: log.completed
                    ? const Color(0xFF2ECC71).withOpacity(0.12)
                    : const Color(0xFFFFD700).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                log.completed ? Icons.check_circle : Icons.fitness_center,
                color: log.completed
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFFFD700),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.workoutName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _dayLabel,
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _Pill('${log.exercises.length} exercises',
                          const Color(0xFF3498DB)),
                      const SizedBox(width: 6),
                      _Pill('$totalSets sets',
                          const Color(0xFF9B59B6)),
                      if (volume > 0) ...[
                        const SizedBox(width: 6),
                        _Pill(
                            '${volume.toStringAsFixed(0)} kg vol',
                            const Color(0xFFE67E22)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF555566), size: 20),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w500)),
      );
}
