import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/workout_database.dart';
import '../models/workout_log.dart';
import '../widgets/empty_state_widget.dart';
import 'export_screen.dart';
import 'workout_logging_screen.dart';
import '../../app_refresh.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen>
    implements RefreshableState {
  final _db = WorkoutDatabase.instance;
  List<WorkoutLog> _logs = [];
  bool _loading = true;

  // Filters (all client-side over the loaded logs)
  String? _typeFilter; // workout name e.g. "Pull A"
  int? _weekdayFilter; // DateTime.weekday 1=Mon … 7=Sun
  DateTimeRange? _dateFilter;

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void refreshData() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final logs = await _db.getAllWorkoutLogs();
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  List<String> get _workoutTypes =>
      _logs.map((l) => l.workoutName).toSet().toList()..sort();

  bool get _hasActiveFilter =>
      _typeFilter != null || _weekdayFilter != null || _dateFilter != null;

  List<WorkoutLog> get _filtered {
    return _logs.where((log) {
      if (_typeFilter != null && log.workoutName != _typeFilter) return false;
      DateTime? d;
      try {
        d = DateTime.parse(log.date);
      } catch (_) {
        d = null;
      }
      if (_weekdayFilter != null && (d == null || d.weekday != _weekdayFilter)) {
        return false;
      }
      if (_dateFilter != null) {
        if (d == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        if (day.isBefore(_dateFilter!.start) || day.isAfter(_dateFilter!.end)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // Groups logs by month label
  Map<String, List<WorkoutLog>> get _grouped {
    final map = <String, List<WorkoutLog>>{};
    for (final log in _filtered) {
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

  void _clearFilters() => setState(() {
        _typeFilter = null;
        _weekdayFilter = null;
        _dateFilter = null;
      });

  Future<void> _pickType() async {
    final types = _workoutTypes;
    final res = await _showOptionSheet(
      'Workout Type',
      [const _Opt('All', null), ...types.map((t) => _Opt(t, t))],
      _typeFilter,
    );
    if (res != null) setState(() => _typeFilter = res.value as String?);
  }

  Future<void> _pickWeekday() async {
    final res = await _showOptionSheet(
      'Day of Week',
      [
        const _Opt('All', null),
        for (int i = 1; i <= 7; i++) _Opt(_weekdayNames[i - 1], i),
      ],
      _weekdayFilter,
    );
    if (res != null) setState(() => _weekdayFilter = res.value as int?);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateFilter,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFD700),
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateFilter = picked);
  }

  // Returns the chosen option, or null if dismissed.
  Future<_Opt?> _showOptionSheet(
      String title, List<_Opt> options, Object? current) {
    return showModalBottomSheet<_Opt>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.map((o) {
                  final selected = o.value == current;
                  return ListTile(
                    title: Text(o.label,
                        style: TextStyle(
                            color: selected
                                ? const Color(0xFFFFD700)
                                : Colors.white,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal)),
                    trailing: selected
                        ? const Icon(Icons.check_rounded,
                            color: Color(0xFFFFD700), size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, o),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    String dateLabel() {
      final r = _dateFilter!;
      final f = DateFormat('MMM d');
      return '${f.format(r.start)} – ${f.format(r.end)}';
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterChip(
            label: _typeFilter ?? 'Type',
            active: _typeFilter != null,
            icon: Icons.fitness_center_rounded,
            onTap: _pickType,
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: _weekdayFilter != null
                ? _weekdayNames[_weekdayFilter! - 1]
                : 'Day',
            active: _weekdayFilter != null,
            icon: Icons.today_rounded,
            onTap: _pickWeekday,
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: _dateFilter != null ? dateLabel() : 'Dates',
            active: _dateFilter != null,
            icon: Icons.date_range_rounded,
            onTap: _pickDateRange,
          ),
          if (_hasActiveFilter) ...[
            const SizedBox(width: 8),
            _filterChip(
              label: 'Clear',
              active: false,
              icon: Icons.close_rounded,
              onTap: _clearFilters,
              danger: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool active,
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final accent =
        danger ? const Color(0xFFE74C3C) : const Color(0xFFFFD700);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.15)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                active ? accent.withValues(alpha: 0.6) : const Color(0xFF2A2A3E),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: active || danger ? accent : const Color(0xFF888899)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: active || danger ? accent : const Color(0xFFCCCCDD),
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500)),
          ],
        ),
      ),
    );
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
              : Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildFilterBar(),
                    const SizedBox(height: 4),
                    Expanded(
                      child: months.isEmpty
                          ? _buildNoMatch()
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
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return const EmptyStateWidget(
      icon: Icons.history_rounded,
      title: 'No workouts yet',
      subtitle: 'Complete your first workout to see it here',
    );
  }

  Widget _buildNoMatch() {
    return const EmptyStateWidget(
      icon: Icons.filter_alt_off_rounded,
      title: 'No workouts match',
      subtitle: 'Try adjusting or clearing your filters',
    );
  }
}

// Option used by the history filter bottom sheets.
class _Opt {
  final String label;
  final Object? value;
  const _Opt(this.label, this.value);
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
