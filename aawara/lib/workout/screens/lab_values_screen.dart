import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/workout_database.dart';
import '../models/lab_value.dart';
import '../../utils/safe_navigation.dart';

class LabValuesScreen extends StatefulWidget {
  const LabValuesScreen({super.key});

  @override
  State<LabValuesScreen> createState() => _LabValuesScreenState();
}

class _LabValuesScreenState extends State<LabValuesScreen> {
  final _db = WorkoutDatabase.instance;
  List<String> _labNames = [];
  Map<String, List<LabValue>> _grouped = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final names = await _db.getLabValueNames();
    final all = await _db.getLabValues();
    final grouped = <String, List<LabValue>>{};
    for (final v in all) {
      grouped.putIfAbsent(v.name, () => []).add(v);
    }
    if (!mounted) return;
    setState(() {
      _labNames = names;
      _grouped = grouped;
      _loading = false;
    });
  }

  Future<void> _editLab(LabValue? existing) async {
    final saved = await showModalBottomSheet<LabValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LabEditorSheet(existing: existing),
    );
    if (saved == null) return;
    await _db.upsertLabValue(saved);
    _load();
  }

  Future<void> _deleteLab(LabValue v) async {
    if (v.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete entry?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Remove ${v.name} = ${_fmtVal(v.value)} from ${v.date}?',
            style: const TextStyle(color: Color(0xFF888899))),
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
      await _db.deleteLabValue(v.id!);
      _load();
    }
  }

  String _fmtVal(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Lab Values',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editLab(null),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _labNames.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFFFFD700),
                  backgroundColor: const Color(0xFF1A1A2E),
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _labNames.length,
                    itemBuilder: (_, i) => _buildLabSection(_labNames[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.science_rounded,
                  color: Color(0xFFFFD700), size: 40),
            ),
            const SizedBox(height: 20),
            const Text('No lab values yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Log TSH, T4, T3, HbA1c, ferritin, vitamin D and any other lab result. Trends are charted per test and out-of-range values are flagged.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF888899), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabSection(String name) {
    final entries = _grouped[name] ?? [];
    if (entries.isEmpty) return const SizedBox.shrink();
    final latest = entries.first;
    final prev = entries.length > 1 ? entries[1] : null;
    final inRange = latest.inRange;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
                if (inRange != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (inRange
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFFE74C3C))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      inRange ? 'IN RANGE' : 'OUT OF RANGE',
                      style: TextStyle(
                        color: inRange
                            ? const Color(0xFF2ECC71)
                            : const Color(0xFFE74C3C),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_fmtVal(latest.value),
                    style: const TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
                if (latest.unit != null) ...[
                  const SizedBox(width: 4),
                  Text(latest.unit!,
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 12)),
                ],
                const SizedBox(width: 10),
                Text(latest.date,
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 11)),
                if (prev != null) ...[
                  const Spacer(),
                  _buildDelta(latest.value, prev.value),
                ],
              ],
            ),
          ),
          if (latest.refLow != null || latest.refHigh != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Reference: ${_fmtRefRange(latest.refLow, latest.refHigh)}'
                '${latest.unit != null ? ' ${latest.unit}' : ''}',
                style: const TextStyle(color: Color(0xFF555577), fontSize: 11),
              ),
            ),
          if (entries.length >= 2) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildChart(entries.reversed.toList(), latest),
              ),
            ),
          ] else
            const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF1E1E35)),
          // Past entries
          for (int i = 0; i < entries.length; i++)
            _buildHistoryRow(entries[i],
                isFirst: i == 0,
                hasNext: i < entries.length - 1),
        ],
      ),
    );
  }

  Widget _buildDelta(double current, double prev) {
    final diff = current - prev;
    if (diff == 0) {
      return const Text('No change',
          style: TextStyle(color: Color(0xFF555577), fontSize: 11));
    }
    final positive = diff > 0;
    return Text(
      '${positive ? '↑' : '↓'}${_fmtVal(diff.abs())}',
      style: TextStyle(
          color: const Color(0xFF888899),
          fontSize: 12,
          fontWeight: FontWeight.w600),
    );
  }

  String _fmtRefRange(double? low, double? high) {
    if (low != null && high != null) return '${_fmtVal(low)}–${_fmtVal(high)}';
    if (low != null) return '≥ ${_fmtVal(low)}';
    if (high != null) return '≤ ${_fmtVal(high)}';
    return '';
  }

  Widget _buildHistoryRow(LabValue v, {required bool isFirst, required bool hasNext}) {
    final inRange = v.inRange;
    return InkWell(
      onLongPress: () => _editLab(v),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: inRange == false
                    ? const Color(0xFFE74C3C)
                    : (isFirst
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF444466)),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(v.date,
                      style: const TextStyle(
                          color: Color(0xFFCCCCDD), fontSize: 13)),
                  const SizedBox(width: 10),
                  Text('${_fmtVal(v.value)}${v.unit != null ? ' ${v.unit}' : ''}',
                      style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Color(0xFF555577), size: 16),
              color: const Color(0xFF1E1E35),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (a) {
                if (a == 'edit') _editLab(v);
                if (a == 'delete') _deleteLab(v);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_rounded,
                          color: Color(0xFFCCCCDD), size: 16),
                      SizedBox(width: 10),
                      Text('Edit',
                          style: TextStyle(color: Color(0xFFCCCCDD))),
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFE74C3C), size: 16),
                      SizedBox(width: 10),
                      Text('Delete',
                          style: TextStyle(color: Color(0xFFE74C3C))),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<LabValue> orderedAsc, LabValue latest) {
    // X-axis = index, Y-axis = value.
    final spots = <FlSpot>[
      for (int i = 0; i < orderedAsc.length; i++)
        FlSpot(i.toDouble(), orderedAsc[i].value),
    ];
    double minY = spots.first.y;
    double maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    if (latest.refLow != null && latest.refLow! < minY) minY = latest.refLow!;
    if (latest.refHigh != null && latest.refHigh! > maxY) {
      maxY = latest.refHigh!;
    }
    final pad = (maxY - minY) * 0.2;
    if (pad == 0) {
      minY = minY - 1;
      maxY = maxY + 1;
    } else {
      minY = minY - pad;
      maxY = maxY + pad;
    }
    final extraLines = <HorizontalLine>[];
    if (latest.refLow != null) {
      extraLines.add(HorizontalLine(
        y: latest.refLow!,
        color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
        strokeWidth: 1,
        dashArray: [4, 4],
      ));
    }
    if (latest.refHigh != null) {
      extraLines.add(HorizontalLine(
        y: latest.refHigh!,
        color: const Color(0xFFE74C3C).withValues(alpha: 0.4),
        strokeWidth: 1,
        dashArray: [4, 4],
      ));
    }
    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: extraLines),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: const Color(0xFFFFD700),
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) {
                final isLatest = spot.x == spots.last.x;
                return FlDotCirclePainter(
                  radius: isLatest ? 4 : 2.5,
                  color: const Color(0xFFFFD700),
                  strokeColor: const Color(0xFF1A1A2E),
                  strokeWidth: isLatest ? 2 : 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFFFFD700).withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabEditorSheet extends StatefulWidget {
  final LabValue? existing;
  const _LabEditorSheet({this.existing});

  @override
  State<_LabEditorSheet> createState() => _LabEditorSheetState();
}

class _LabEditorSheetState extends State<_LabEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _refLowCtrl;
  late final TextEditingController _refHighCtrl;
  late DateTime _date;

  // Suggested labs with common units & reference ranges
  static const _suggestions = [
    ('TSH', 'mIU/L', 0.4, 4.0),
    ('Free T4', 'ng/dL', 0.8, 1.8),
    ('Free T3', 'pg/mL', 2.3, 4.2),
    ('TPO antibody', 'U/mL', null, 34.0),
    ('HbA1c', '%', null, 5.7),
    ('Fasting glucose', 'mg/dL', 70.0, 99.0),
    ('Vitamin D3', 'nmol/L', 75.0, 200.0),
    ('B12', 'pg/mL', 200.0, 900.0),
    ('Ferritin', 'ng/mL', 30.0, 400.0),
    ('Total testosterone', 'ng/dL', 300.0, 900.0),
    ('Free testosterone', 'pg/mL', 9.0, 30.0),
    ('Total cholesterol', 'mg/dL', null, 200.0),
    ('HDL', 'mg/dL', 40.0, null),
    ('LDL', 'mg/dL', null, 130.0),
    ('Triglycerides', 'mg/dL', null, 150.0),
    ('Cortisol', 'µg/dL', 6.0, 23.0),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _valueCtrl = TextEditingController(text: e == null ? '' : _fmt(e.value));
    _unitCtrl = TextEditingController(text: e?.unit ?? '');
    _refLowCtrl =
        TextEditingController(text: e?.refLow == null ? '' : _fmt(e!.refLow!));
    _refHighCtrl = TextEditingController(
        text: e?.refHigh == null ? '' : _fmt(e!.refHigh!));
    _date = e != null ? DateTime.parse(e.date) : DateTime.now();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    _unitCtrl.dispose();
    _refLowCtrl.dispose();
    _refHighCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFD700),
            surface: Color(0xFF1A1A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _applySuggestion((String, String, double?, double?) s) {
    setState(() {
      _nameCtrl.text = s.$1;
      _unitCtrl.text = s.$2;
      _refLowCtrl.text = s.$3 == null ? '' : _fmt(s.$3!);
      _refHighCtrl.text = s.$4 == null ? '' : _fmt(s.$4!);
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final value = double.tryParse(_valueCtrl.text);
    if (name.isEmpty || value == null) return;
    final v = LabValue(
      id: widget.existing?.id,
      date: _fmtDate(_date),
      name: name,
      value: value,
      unit: _unitCtrl.text.trim().isEmpty ? null : _unitCtrl.text.trim(),
      refLow: double.tryParse(_refLowCtrl.text),
      refHigh: double.tryParse(_refHighCtrl.text),
    );
    popAfterFocusSettles(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFF333355),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.existing == null ? 'Add lab value' : 'Edit lab value',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (widget.existing == null) ...[
                const Text('Quick pick',
                    style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final s = _suggestions[i];
                      return GestureDetector(
                        onTap: () => _applySuggestion(s),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D1A),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: const Color(0xFF2A2A45)),
                          ),
                          child: Text(s.$1,
                              style: const TextStyle(
                                  color: Color(0xFFCCCCDD),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _sectionLabel('Name'),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _input('e.g. TSH, HbA1c'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Value'),
                        TextField(
                          controller: _valueCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('e.g. 2.92'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Unit'),
                        TextField(
                          controller: _unitCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('mIU/L'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Ref low (optional)'),
                        TextField(
                          controller: _refLowCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('0.4'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Ref high (optional)'),
                        TextField(
                          controller: _refHighCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*'))
                          ],
                          style: const TextStyle(color: Colors.white),
                          decoration: _input('4.0'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _sectionLabel('Date'),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2A2A45)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: Color(0xFFFFD700), size: 16),
                      const SizedBox(width: 10),
                      Text(_fmtDate(_date),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(widget.existing == null ? 'Add' : 'Save',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(s,
            style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF444466)),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFFD700))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}
