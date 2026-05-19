import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import 'exercise_progress_screen.dart' show exerciseColor;

enum _Metric { orm, weight, volume }

enum _Range { m1, m3, m6, y1 }

class ExerciseProgressDetailScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseProgressDetailScreen({super.key, required this.exercise});

  @override
  State<ExerciseProgressDetailScreen> createState() =>
      _ExerciseProgressDetailScreenState();
}

class _ExerciseProgressDetailScreenState
    extends State<ExerciseProgressDetailScreen> {
  final _db = WorkoutDatabase.instance;

  _Metric _metric = _Metric.orm;
  _Range _range = _Range.m3;

  // Chart data
  List<Map<String, dynamic>> _chartData = [];
  bool _chartLoading = false;

  // Stats
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _prHistory = [];
  Map<String, dynamic>? _pr;
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadChart();
  }

  Color get _color => exerciseColor(widget.exercise.muscleGroup);

  String get _fromDate {
    final now = DateTime.now();
    return switch (_range) {
      _Range.m1 => _fmt(now.subtract(const Duration(days: 30))),
      _Range.m3 => _fmt(now.subtract(const Duration(days: 90))),
      _Range.m6 => _fmt(now.subtract(const Duration(days: 180))),
      _Range.y1 => _fmt(now.subtract(const Duration(days: 365))),
    };
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _metricKey => switch (_metric) {
        _Metric.orm => 'orm',
        _Metric.weight => 'weight',
        _Metric.volume => 'volume',
      };

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final stats = await _db.getExerciseTotalStats(widget.exercise.id);
    final sessions =
        await _db.getRecentSessionsForExercise(widget.exercise.id);
    final prHistory =
        await _db.getPRHistoryForExercise(widget.exercise.id);
    final pr = await _db.getPRForExercise(widget.exercise.id);
    if (mounted) {
      setState(() {
        _stats = stats;
        _sessions = sessions;
        _prHistory = prHistory;
        _pr = pr;
        _statsLoading = false;
      });
    }
  }

  Future<void> _loadChart() async {
    setState(() => _chartLoading = true);
    final data = await _db.getExerciseChartData(
        widget.exercise.id, _metricKey, _fromDate);
    if (mounted) {
      setState(() {
        _chartData = data;
        _chartLoading = false;
      });
    }
  }

  // ─── Chart helpers ─────────────────────────────────────────────────────────

  List<FlSpot> get _spots {
    return List.generate(
      _chartData.length,
      (i) => FlSpot(i.toDouble(), ((_chartData[i]['value'] as num?)?.toDouble() ?? 0)),
    );
  }

  String _xLabel(int index) {
    if (index < 0 || index >= _chartData.length) return '';
    final date = _chartData[index]['date'] as String;
    try {
      final d = DateTime.parse(date);
      return switch (_range) {
        _Range.m1 => DateFormat('d/M').format(d),
        _Range.m3 => DateFormat('d MMM').format(d),
        _Range.m6 => DateFormat('MMM').format(d),
        _Range.y1 => DateFormat('MMM').format(d),
      };
    } catch (_) {
      return '';
    }
  }

  double get _currentVal =>
      _spots.isNotEmpty ? _spots.last.y : 0;
  double get _startVal =>
      _spots.isNotEmpty ? _spots.first.y : 0;
  double get _delta => _currentVal - _startVal;
  double get _deltaPct =>
      _startVal > 0 ? (_delta / _startVal * 100) : 0;

  String _fmtVal(double v) {
    if (_metric == _Metric.volume) {
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
      return v.toStringAsFixed(0);
    }
    return v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
  }

  String _fmtW(double w) =>
      w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final prWeight = (_pr?['weight'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          children: [
            Text(
              ex.muscleGroup.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              ex.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _statsLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              children: [
                const SizedBox(height: 4),
                // PR headline card
                _buildPRCard(prWeight),
                const SizedBox(height: 14),
                // Metric segmented control
                _buildMetricToggle(),
                const SizedBox(height: 12),
                // Chart card
                _buildChartCard(),
                const SizedBox(height: 12),
                // Quick stat grid
                _buildStatsGrid(),
                const SizedBox(height: 20),
                _sectionHeader('RECENT SESSIONS'),
                const SizedBox(height: 10),
                _buildRecentSessions(),
                if (_prHistory.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionHeader('PR HISTORY'),
                  const SizedBox(height: 10),
                  _buildPRHistory(),
                ],
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _sectionHeader(String label) => Text(
        label,
        style: const TextStyle(
          color: Color(0xFF888899),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );

  // ─── PR headline ───────────────────────────────────────────────────────────

  Widget _buildPRCard(double prWeight) {
    final prDate = _pr?['date'] as String?;
    String dateLabel = '';
    if (prDate != null) {
      try {
        final d = DateTime.parse(prDate);
        final diff = DateTime.now().difference(d).inDays;
        dateLabel = diff == 0
            ? 'Today'
            : diff == 1
                ? 'Yesterday'
                : '$diff days ago';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _color.withValues(alpha: 0.12),
            _color.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PERSONAL RECORD',
                  style: TextStyle(
                    color: _color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      prWeight > 0 ? _fmtW(prWeight) : '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (prWeight > 0) ...[
                      const SizedBox(width: 6),
                      const Text(
                        'kg',
                        style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 12),
                  ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child:
                const Icon(Icons.emoji_events_rounded, color: Color(0xFF2A1A06), size: 26),
          ),
        ],
      ),
    );
  }

  // ─── Metric toggle ─────────────────────────────────────────────────────────

  Widget _buildMetricToggle() {
    const options = [
      (_Metric.orm, 'Est. 1RM'),
      (_Metric.weight, 'Top Set'),
      (_Metric.volume, 'Volume'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: options.map((opt) {
          final (metric, label) = opt;
          final selected = _metric == metric;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _metric = metric);
                _loadChart();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1A1A2E)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: selected
                      ? Border.all(
                          color: const Color(0xFF333355))
                      : null,
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color:
                          selected ? Colors.white : const Color(0xFF888899),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Chart card ────────────────────────────────────────────────────────────

  Widget _buildChartCard() {
    final metricLabel = switch (_metric) {
      _Metric.orm => 'Estimated 1RM',
      _Metric.weight => 'Working Weight',
      _Metric.volume => 'Volume per Session',
    };
    final unit = _metric == _Metric.volume ? 'kg' : 'kg';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metricLabel,
                        style: const TextStyle(
                            color: Color(0xFF888899),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _chartData.isNotEmpty
                              ? _fmtVal(_currentVal)
                              : '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(unit,
                            style: const TextStyle(
                                color: Color(0xFF888899), fontSize: 11)),
                        if (_chartData.length > 1 && _delta > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2ECC71)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.trending_up_rounded,
                                    color: Color(0xFF2ECC71), size: 11),
                                const SizedBox(width: 2),
                                Text(
                                  '+${_deltaPct.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Color(0xFF2ECC71),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Range pills
              Row(
                children: [
                  _Range.m1,
                  _Range.m3,
                  _Range.m6,
                  _Range.y1,
                ].map((r) {
                  final label = switch (r) {
                    _Range.m1 => '1M',
                    _Range.m3 => '3M',
                    _Range.m6 => '6M',
                    _Range.y1 => '1Y',
                  };
                  final selected = _range == r;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _range = r);
                      _loadChart();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: selected ? _color : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? Colors.black
                              : const Color(0xFF888899),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Chart
          SizedBox(
            height: 180,
            child: _chartLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFFFFD700), strokeWidth: 2))
                : _chartData.length < 2
                    ? Center(
                        child: Text(
                          'Not enough data for this period',
                          style: TextStyle(
                              color: _color.withValues(alpha: 0.5),
                              fontSize: 13),
                        ),
                      )
                    : _buildLineChart(),
          ),
          // Start / Change / Current
          if (_chartData.length >= 2) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1E1E35), height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statCell('Start', '${_fmtVal(_startVal)} $unit'),
                _statCell(
                  'Change',
                  '${_delta >= 0 ? '+' : ''}${_fmtVal(_delta)} $unit',
                  valueColor: _delta >= 0
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFFE74C3C),
                ),
                _statCell('Current', '${_fmtVal(_currentVal)} $unit'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, {Color? valueColor}) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF888899), fontSize: 11)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }

  Widget _buildLineChart() {
    final spots = _spots;
    final minY =
        spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.96;
    final maxY =
        spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.04;

    // Choose which x indices to label (max ~5 labels)
    final labelStep =
        spots.length <= 5 ? 1 : (spots.length / 4).ceil();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: const Color(0xFF1E1E35),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, _) => Text(
                _fmtVal(v),
                style: const TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 9,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: labelStep.toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i % labelStep != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _xLabel(i),
                    style: const TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 9,
                        fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1A2E),
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '${_fmtVal(s.y)} kg',
                TextStyle(
                    color: _color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: _color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, i) {
                final isLast = i == spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 3,
                  color: isLast ? _color : const Color(0xFF0D0D1A),
                  strokeWidth: 2,
                  strokeColor: _color,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _color.withValues(alpha: 0.25),
                  _color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick stat grid ───────────────────────────────────────────────────────

  Widget _buildStatsGrid() {
    final sessions = _stats['sessions'] as int? ?? 0;
    final sets = _stats['total_sets'] as int? ?? 0;
    final reps = _stats['total_reps'] as int? ?? 0;
    final vol = (_stats['total_volume'] as double?) ?? 0.0;

    String fmtVol(double v) {
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}Mt';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}t';
      return '${v.toStringAsFixed(0)} kg';
    }

    final items = [
      ('$sessions', 'Total Sessions', _color),
      ('$sets', 'Total Sets', const Color(0xFFFFD700)),
      ('$reps', 'Total Reps', const Color(0xFF60A5FA)),
      (fmtVol(vol), 'Lifetime Vol.', const Color(0xFFF472B6)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((item) {
        final (value, label, color) = item;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF12121F),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 11)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Recent sessions ───────────────────────────────────────────────────────

  Widget _buildRecentSessions() {
    if (_sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('No sessions yet',
            style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _sessions.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final date = s['date'] as String;
          final sets = (s['sets'] as List).cast<Map<String, dynamic>>();
          final topW = s['top_weight'] as double;
          final topR = s['top_reps'] as int;
          final isPR = s['is_pr'] as bool? ?? false;

          String dateLabel;
          try {
            final d = DateTime.parse(date);
            final diff = DateTime.now().difference(d).inDays;
            dateLabel = diff == 0
                ? 'Today'
                : diff == 1
                    ? 'Yesterday'
                    : '$diff days ago';
          } catch (_) {
            dateLabel = date;
          }

          return Container(
            decoration: BoxDecoration(
              border: i < _sessions.length - 1
                  ? const Border(
                      bottom:
                          BorderSide(color: Color(0xFF1E1E35), width: 1))
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(dateLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    if (isPR) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('NEW PR',
                            style: TextStyle(
                                color: Color(0xFF2A1A06),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${_fmtW(topW)} × $topR',
                      style: TextStyle(
                        color: _color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: sets.map((set) {
                    final w = set['weight'] as double;
                    final r = set['reps'] as int;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: _fmtW(w),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                            const TextSpan(
                              text: ' × ',
                              style: TextStyle(
                                  color: Color(0xFF888899), fontSize: 11),
                            ),
                            TextSpan(
                              text: '$r',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── PR history ────────────────────────────────────────────────────────────

  Widget _buildPRHistory() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _prHistory.take(6).toList().asMap().entries.map((entry) {
          final i = entry.key;
          final pr = entry.value;
          final w = pr['weight'] as double;
          final date = pr['date'] as String;
          final isLatest = i == 0;

          String dateLabel;
          try {
            final d = DateTime.parse(date);
            final diff = DateTime.now().difference(d).inDays;
            dateLabel = diff == 0
                ? 'Today'
                : diff == 1
                    ? 'Yesterday'
                    : '$diff days ago';
          } catch (_) {
            dateLabel = date;
          }

          // Delta vs previous PR
          String delta = '';
          if (i < _prHistory.length - 1) {
            final prevW = _prHistory[i + 1]['weight'] as double;
            final d = w - prevW;
            delta = '+${_fmtW(d)} kg';
          }

          final rank = _prHistory.length - i;

          return Container(
            decoration: BoxDecoration(
              border: i < (_prHistory.length - 1).clamp(0, 5)
                  ? const Border(
                      bottom: BorderSide(color: Color(0xFF1E1E35), width: 1))
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isLatest
                        ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                        : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: isLatest
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF888899),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_fmtW(w)} kg',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(dateLabel,
                          style: const TextStyle(
                              color: Color(0xFF888899), fontSize: 11)),
                    ],
                  ),
                ),
                if (delta.isNotEmpty)
                  Text(delta,
                      style: const TextStyle(
                          color: Color(0xFF2ECC71),
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
