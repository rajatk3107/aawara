import 'package:flutter/material.dart';
import '../database/workout_database.dart';

class WorkoutHeatmap extends StatefulWidget {
  final int months;
  final double cellSize;

  const WorkoutHeatmap({
    super.key,
    this.months = 6,
    this.cellSize = 10,
  });

  @override
  State<WorkoutHeatmap> createState() => _WorkoutHeatmapState();
}

class _WorkoutHeatmapState extends State<WorkoutHeatmap> {
  final _db = WorkoutDatabase.instance;
  Map<String, int> _counts = {};
  bool _loading = true;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _dayLabels = ['M', '', 'W', '', 'F', '', ''];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WorkoutHeatmap old) {
    super.didUpdateWidget(old);
    if (old.months != widget.months) _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final today = DateTime.now();
    final from = today.subtract(Duration(days: widget.months * 30));
    final counts = await _db.getWorkoutCountsByDate(
        _fmt(from), _fmt(today));
    if (mounted) setState(() { _counts = counts; _loading = false; });
  }

  Color _cellColor(int count) {
    if (count <= 0) return const Color(0xFF1A1A2E);
    if (count == 1) return const Color(0xFFFFD700).withValues(alpha: 0.3);
    if (count == 2) return const Color(0xFFFFD700).withValues(alpha: 0.6);
    return const Color(0xFFFFD700);
  }

  Future<void> _onTapCell(String dateStr) async {
    final summaries = await _db.getWorkoutSummaryForDate(dateStr);
    if (!mounted) return;
    final parsed = DateTime.parse(dateStr);
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label = '${dayNames[parsed.weekday - 1]} '
        '${_monthNames[parsed.month - 1]} ${parsed.day}';
    final detail = summaries.map((r) {
      final name = r['workout_name'] as String;
      final vol = (r['total_volume'] as num? ?? 0).toDouble();
      return vol > 0 ? '$name · ${vol.toInt()} kg' : name;
    }).join('  ·  ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '$label  ·  $detail',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      backgroundColor: const Color(0xFF2A2A45),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFFFD700)),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fromDay = today.subtract(Duration(days: widget.months * 30));
    final startMonday =
        fromDay.subtract(Duration(days: fromDay.weekday - 1));

    final weekMondays = <DateTime>[];
    DateTime cursor = startMonday;
    while (!cursor.isAfter(today)) {
      weekMondays.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }

    const gap = 2.0;
    final cs = widget.cellSize;

    final fromStr = _fmt(fromDay);
    final todayStr = _fmt(today);

    // Month labels: first column where a new month appears in range
    final monthLabelByCol = <int, String>{};
    int? lastMonth;
    for (int i = 0; i < weekMondays.length; i++) {
      for (int d = 0; d < 7; d++) {
        final day = weekMondays[i].add(Duration(days: d));
        final ds = _fmt(day);
        if (ds >= fromStr && ds <= todayStr) {
          if (day.month != lastMonth) {
            monthLabelByCol[i] = _monthNames[day.month - 1];
            lastMonth = day.month;
          }
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed day-of-week labels
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(height: 14 + gap),
                ...List.generate(7, (i) => Container(
                  width: 12,
                  height: cs,
                  margin: EdgeInsets.only(bottom: i < 6 ? gap : 0),
                  alignment: Alignment.centerLeft,
                  child: _dayLabels[i].isNotEmpty
                      ? Text(_dayLabels[i],
                          style: const TextStyle(
                              color: Color(0xFF444466), fontSize: 8))
                      : null,
                )),
              ],
            ),
            const SizedBox(width: 4),
            // Scrollable week grid
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: weekMondays.asMap().entries.map((entry) {
                    final colIdx = entry.key;
                    final mon = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(right: gap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 14,
                            child: monthLabelByCol.containsKey(colIdx)
                                ? Text(monthLabelByCol[colIdx]!,
                                    style: const TextStyle(
                                        color: Color(0xFF555577),
                                        fontSize: 9))
                                : null,
                          ),
                          SizedBox(height: gap),
                          ...List.generate(7, (d) {
                            final day = mon.add(Duration(days: d));
                            final dateStr = _fmt(day);
                            final inRange =
                                dateStr >= fromStr && dateStr <= todayStr;
                            final count =
                                inRange ? (_counts[dateStr] ?? 0) : -1;
                            return GestureDetector(
                              onTap: count > 0
                                  ? () => _onTapCell(dateStr)
                                  : null,
                              child: Container(
                                width: cs,
                                height: cs,
                                margin: EdgeInsets.only(
                                    bottom: d < 6 ? gap : 0),
                                decoration: BoxDecoration(
                                  color: count < 0
                                      ? Colors.transparent
                                      : _cellColor(count),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text('Less',
                style: TextStyle(color: Color(0xFF444466), fontSize: 9)),
            const SizedBox(width: 4),
            ...[0, 1, 2, 3].map((c) => Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _cellColor(c),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            const SizedBox(width: 4),
            const Text('More',
                style: TextStyle(color: Color(0xFF444466), fontSize: 9)),
          ],
        ),
      ],
    );
  }
}
