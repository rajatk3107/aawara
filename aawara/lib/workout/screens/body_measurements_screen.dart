import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database/workout_database.dart';
import '../../utils/safe_navigation.dart';

// ─── Measurement type definitions ────────────────────────────────────────────

class MeasurementType {
  final String key;
  final String label;
  final String emoji;
  final Color color;
  const MeasurementType(this.key, this.label, this.emoji, this.color);
}

const kMeasurementTypes = [
  MeasurementType('neck', 'Neck', '🔵', Color(0xFF9B59B6)),
  MeasurementType('shoulders', 'Shoulders', '💪', Color(0xFF3498DB)),
  MeasurementType('chest', 'Chest', '❤️', Color(0xFFE74C3C)),
  MeasurementType('biceps', 'Biceps', '💪', Color(0xFFFFD700)),
  MeasurementType('forearms', 'Forearms', '🤜', Color(0xFFF39C12)),
  MeasurementType('waist', 'Waist', '📏', Color(0xFF2ECC71)),
  MeasurementType('abdomen', 'Abdomen', '🔘', Color(0xFF1ABC9C)),
  MeasurementType('hips', 'Hips', '📐', Color(0xFFFF6B35)),
  MeasurementType('glutes', 'Glutes', '🍑', Color(0xFFE67E22)),
  MeasurementType('thighs', 'Thighs', '🦵', Color(0xFF8E44AD)),
  MeasurementType('calves', 'Calves', '🦶', Color(0xFF2980B9)),
];

MeasurementType? measurementTypeByKey(String key) =>
    kMeasurementTypes.cast<MeasurementType?>().firstWhere(
        (t) => t?.key == key,
        orElse: () => null);

// ─── Screen ───────────────────────────────────────────────────────────────────

class BodyMeasurementsScreen extends StatefulWidget {
  const BodyMeasurementsScreen({super.key});

  @override
  State<BodyMeasurementsScreen> createState() => _BodyMeasurementsScreenState();
}

class _BodyMeasurementsScreenState extends State<BodyMeasurementsScreen> {
  final _db = WorkoutDatabase.instance;

  Map<String, double> _latest = {};
  Map<String, String> _latestDates = {};
  bool _loading = true;

  // Inline chart selection
  String? _selectedKey;
  List<Map<String, dynamic>> _chartData = [];
  bool _chartLoading = false;

  // History entries (last 60 days)
  List<String> _dates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getLatestMeasurements(),
      _db.getLatestMeasurementDates(),
      _db.getMeasurementDates(),
    ]);
    if (!mounted) return;
    setState(() {
      _latest = results[0] as Map<String, double>;
      _latestDates = results[1] as Map<String, String>;
      _dates = results[2] as List<String>;
      _loading = false;
    });
  }

  Future<void> _selectType(String key) async {
    if (_selectedKey == key) {
      setState(() => _selectedKey = null);
      return;
    }
    setState(() {
      _selectedKey = key;
      _chartLoading = true;
      _chartData = [];
    });
    final data = await _db.getMeasurementHistory(key);
    if (!mounted) return;
    setState(() {
      _chartData = data;
      _chartLoading = false;
    });
  }

  Future<void> _openLogSheet([String? date]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogMeasurementsSheet(
        initialDate: date ?? _todayStr(),
        existing: date != null ? {} : _latest,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _deleteEntry(String date, String type) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete entry',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove ${measurementTypeByKey(type)?.label ?? type} on $date?',
          style: const TextStyle(color: Color(0xFFCCCCDD)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteMeasurement(date, type);
      _load();
      if (_selectedKey == type) {
        final data = await _db.getMeasurementHistory(type);
        if (mounted) setState(() => _chartData = data);
      }
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Body Measurements',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Color(0xFFFFD700)),
            tooltip: 'Log today',
            onPressed: _openLogSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _buildLogButton(),
                const SizedBox(height: 20),
                _buildSectionHeader('CURRENT MEASUREMENTS'),
                const SizedBox(height: 12),
                _buildMeasurementGrid(),
                if (_selectedKey != null) ...[
                  const SizedBox(height: 20),
                  _buildChartSection(),
                ],
                if (_dates.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _buildSectionHeader('HISTORY'),
                  const SizedBox(height: 12),
                  _buildHistoryList(),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openLogSheet,
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.straighten_rounded),
        label: const Text('Log Measurements',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLogButton() {
    return GestureDetector(
      onTap: _openLogSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1800), Color(0xFF1A1A2E)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.straighten_rounded,
                  color: Color(0xFFFFD700), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Log Today\'s Measurements',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Track waist, chest, thighs, biceps & more',
                      style:
                          TextStyle(color: Color(0xFF888899), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFFFD700), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF888899),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );

  Widget _buildMeasurementGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: kMeasurementTypes.length,
      itemBuilder: (_, i) {
        final mt = kMeasurementTypes[i];
        final val = _latest[mt.key];
        final date = _latestDates[mt.key];
        final isSelected = _selectedKey == mt.key;
        return GestureDetector(
          onTap: () => _selectType(mt.key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? mt.color.withValues(alpha: 0.15)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? mt.color.withValues(alpha: 0.6)
                    : const Color(0xFF2A2A3E),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mt.emoji, style: const TextStyle(fontSize: 18)),
                const Spacer(),
                Text(
                  val != null ? '${_fmtVal(val)} cm' : '—',
                  style: TextStyle(
                    color: val != null ? mt.color : const Color(0xFF444466),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mt.label,
                  style: const TextStyle(
                      color: Color(0xFFCCCCDD),
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                if (date != null)
                  Text(
                    _shortDate(date),
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 9),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartSection() {
    final mt = measurementTypeByKey(_selectedKey!)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: mt.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              '${mt.label} History',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_chartLoading)
          const SizedBox(
            height: 160,
            child: Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFFFD700), strokeWidth: 2)),
          )
        else if (_chartData.isEmpty)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('No history yet',
                  style: TextStyle(color: Color(0xFF555577))),
            ),
          )
        else
          _buildChart(mt),
      ],
    );
  }

  Widget _buildChart(MeasurementType mt) {
    final spots = <FlSpot>[];
    final dateMap = <double, String>{};
    for (int i = 0; i < _chartData.length; i++) {
      final r = _chartData[i];
      spots.add(FlSpot(i.toDouble(), (r['value_cm'] as num).toDouble()));
      dateMap[i.toDouble()] = r['date'] as String;
    }
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) < 3 ? 3.0 : (maxY - minY) * 0.2;

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY - yPad,
          maxY: maxY + yPad,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF1E1E35), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (v, _) => Text(
                  '${v.toStringAsFixed(1)}',
                  style:
                      const TextStyle(color: Color(0xFF888899), fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: spots.length > 5
                    ? (spots.length / 4).roundToDouble()
                    : 1,
                getTitlesWidget: (v, _) {
                  final d = dateMap[v];
                  if (d == null) return const SizedBox.shrink();
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('d/M').format(DateTime.parse(d)),
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 9),
                      ),
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: mt.color,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: mt.color,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF0D0D1A),
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: mt.color.withValues(alpha: 0.08),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF12121F),
              tooltipBorder: BorderSide(color: mt.color.withValues(alpha: 0.5)),
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} cm\n',
                        TextStyle(
                            color: mt.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        children: [
                          TextSpan(
                            text: dateMap[s.x] ?? '',
                            style: const TextStyle(
                                color: Color(0xFF888899),
                                fontSize: 10,
                                fontWeight: FontWeight.normal),
                          ),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _dates.take(30).length,
      itemBuilder: (_, i) {
        final date = _dates[i];
        return _HistoryDateCard(
          date: date,
          db: _db,
          onDelete: (type) => _deleteEntry(date, type),
          onEdit: () => _openLogSheet(date),
        );
      },
    );
  }

  String _fmtVal(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _shortDate(String date) {
    try {
      return DateFormat('d MMM yy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }
}

// ─── History date card ────────────────────────────────────────────────────────

class _HistoryDateCard extends StatefulWidget {
  final String date;
  final WorkoutDatabase db;
  final void Function(String type) onDelete;
  final VoidCallback onEdit;

  const _HistoryDateCard({
    required this.date,
    required this.db,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_HistoryDateCard> createState() => _HistoryDateCardState();
}

class _HistoryDateCardState extends State<_HistoryDateCard> {
  Map<String, double>? _measurements;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await widget.db.getMeasurementsForDate(widget.date);
    if (mounted) setState(() => _measurements = m);
  }

  String _fmtDate(String date) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _measurements;
    if (m == null || m.isEmpty) return const SizedBox.shrink();

    final types = kMeasurementTypes.where((t) => m.containsKey(t.key)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      color: Color(0xFF555577), size: 15),
                  const SizedBox(width: 10),
                  Text(
                    _fmtDate(widget.date),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${types.length} measurement${types.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 12),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 17, color: Color(0xFF888899)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onEdit,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF555577),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: types.map((mt) {
                  final val = m[mt.key]!;
                  final fmtVal = val == val.truncateToDouble()
                      ? val.toInt().toString()
                      : val.toStringAsFixed(1);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: mt.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(mt.label,
                            style: const TextStyle(
                                color: Color(0xFFCCCCDD), fontSize: 13)),
                        const Spacer(),
                        Text('$fmtVal cm',
                            style: TextStyle(
                                color: mt.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => widget.onDelete(mt.key),
                          child: const Icon(Icons.close,
                              size: 14, color: Color(0xFF444466)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Log measurements sheet ───────────────────────────────────────────────────

class _LogMeasurementsSheet extends StatefulWidget {
  final String initialDate;
  final Map<String, double> existing;

  const _LogMeasurementsSheet({
    required this.initialDate,
    required this.existing,
  });

  @override
  State<_LogMeasurementsSheet> createState() => _LogMeasurementsSheetState();
}

class _LogMeasurementsSheetState extends State<_LogMeasurementsSheet> {
  final _db = WorkoutDatabase.instance;
  late String _date;
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _controllers = {
      for (final mt in kMeasurementTypes)
        mt.key: TextEditingController(
          text: widget.existing[mt.key] != null
              ? _fmtVal(widget.existing[mt.key]!)
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtVal(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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
    if (picked != null) {
      setState(() {
        _date =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _save() async {
    final entries = <String, double>{};
    for (final mt in kMeasurementTypes) {
      final text = _controllers[mt.key]!.text.trim();
      if (text.isEmpty) continue;
      final val = double.tryParse(text);
      if (val != null && val > 0) {
        entries[mt.key] = val;
      }
    }

    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter at least one measurement'),
        backgroundColor: Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _saving = true);
    for (final e in entries.entries) {
      await _db.logMeasurement(_date, e.key, e.value);
    }
    if (!mounted) return;
    popAfterFocusSettles(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.98,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF444466),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 16, 4),
              child: Row(
                children: [
                  const Text(
                    'Log Measurements',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF888899))),
                  ),
                ],
              ),
            ),
            // Date picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF333355)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: Color(0xFFFFD700), size: 16),
                    const SizedBox(width: 10),
                    Text(
                      () {
                        try {
                          return DateFormat('EEEE, MMM d, yyyy')
                              .format(DateTime.parse(_date));
                        } catch (_) {
                          return _date;
                        }
                      }(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const Spacer(),
                    const Text('Change',
                        style: TextStyle(
                            color: Color(0xFF555577), fontSize: 12)),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Enter measurements in cm. Leave blank to skip.',
                style: TextStyle(color: Color(0xFF555577), fontSize: 12),
              ),
            ),
            const Divider(color: Color(0xFF1E1E35), height: 1),
            // Fields
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: kMeasurementTypes.length,
                itemBuilder: (_, i) {
                  final mt = kMeasurementTypes[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: mt.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(mt.emoji,
                                style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            mt.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _controllers[mt.key],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d{0,3}\.?\d{0,1}')),
                            ],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: mt.color,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              hintText: '—',
                              hintStyle: const TextStyle(
                                  color: Color(0xFF444466), fontSize: 16),
                              suffixText: 'cm',
                              suffixStyle: const TextStyle(
                                  color: Color(0xFF555577), fontSize: 12),
                              filled: true,
                              fillColor: const Color(0xFF1A1A2E),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: mt.color.withValues(alpha: 0.5)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Save button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Text(
                          'Save Measurements',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
