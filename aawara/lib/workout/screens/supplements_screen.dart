import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/workout_database.dart';
import '../models/supplement.dart';
import '../../services/notification_service.dart';
import '../../utils/safe_navigation.dart';

class SupplementsScreen extends StatefulWidget {
  const SupplementsScreen({super.key});

  @override
  State<SupplementsScreen> createState() => _SupplementsScreenState();
}

class _SupplementsScreenState extends State<SupplementsScreen> {
  final _db = WorkoutDatabase.instance;

  List<Supplement> _supplements = [];
  Set<int> _takenToday = {};
  Map<int, int> _adherence = {};
  bool _loading = true;

  String get _todayDate {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getSupplements(),
      _db.getSupplementsTakenOn(_todayDate),
      _db.getSupplementAdherence(days: 7),
    ]);
    if (!mounted) return;
    setState(() {
      _supplements = results[0] as List<Supplement>;
      _takenToday = results[1] as Set<int>;
      _adherence = results[2] as Map<int, int>;
      _loading = false;
    });
  }

  Future<void> _toggleTaken(Supplement s) async {
    if (s.id == null) return;
    HapticFeedback.lightImpact();
    if (_takenToday.contains(s.id)) {
      await _db.unmarkSupplementTaken(s.id!, _todayDate);
    } else {
      await _db.markSupplementTaken(s.id!, _todayDate);
    }
    _load();
  }

  Future<void> _editSupplement(Supplement? existing) async {
    final result = await showModalBottomSheet<Supplement>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplementEditorSheet(existing: existing),
    );
    if (result == null || !mounted) return;
    final id = await _db.upsertSupplement(result);
    final saved = result.copyWith(id: id);
    // Schedule reminder
    try {
      final parts = saved.timeHhmm.split(':');
      await NotificationService.instance.scheduleDailyReminder(
        id: 1000 + id,
        time: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        title: '💊 ${saved.name}',
        body: saved.dose != null && saved.dose!.isNotEmpty
            ? '${saved.dose} · tap to mark taken'
            : 'Tap to mark taken',
      );
    } catch (_) {}
    _load();
  }

  Future<void> _deleteSupplement(Supplement s) async {
    if (s.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete supplement?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove "${s.name}" and all its log history?',
          style: const TextStyle(color: Color(0xFF888899), height: 1.4),
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
    if (confirm != true) return;
    await _db.deleteSupplement(s.id!);
    try {
      await NotificationService.instance.cancelById(1000 + s.id!);
    } catch (_) {}
    _load();
  }

  int get _takenCount => _takenToday.length;
  int get _totalCount => _supplements.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Supplements',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSupplement(null),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _supplements.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: const Color(0xFFFFD700),
                  backgroundColor: const Color(0xFF1A1A2E),
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      _buildTodaySummary(),
                      const SizedBox(height: 16),
                      ..._buildTimelineGroups(),
                    ],
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
              child: const Icon(Icons.medication_rounded,
                  color: Color(0xFFFFD700), size: 40),
            ),
            const SizedBox(height: 20),
            const Text('No supplements yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Add your supplements with their timing.\nDaily reminders fire at the chosen time and you can mark each one as taken from this screen or the notification.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF888899), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySummary() {
    final pct = _totalCount == 0 ? 0.0 : _takenCount / _totalCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TODAY',
                style: TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2),
              ),
              const Spacer(),
              Text(
                '$_takenCount / $_totalCount taken',
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: AlwaysStoppedAnimation(
                pct >= 1.0
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFFFD700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTimelineGroups() {
    // Group by time-of-day bucket (morning / midday / evening / night)
    final morning = <Supplement>[];
    final midday = <Supplement>[];
    final evening = <Supplement>[];
    final night = <Supplement>[];
    for (final s in _supplements) {
      final h = int.tryParse(s.timeHhmm.split(':').first) ?? 12;
      if (h < 11) {
        morning.add(s);
      } else if (h < 16) {
        midday.add(s);
      } else if (h < 20) {
        evening.add(s);
      } else {
        night.add(s);
      }
    }
    final widgets = <Widget>[];
    if (morning.isNotEmpty) {
      widgets.add(_buildGroup('🌅 Morning', morning));
    }
    if (midday.isNotEmpty) {
      widgets.add(_buildGroup('☀️ Midday', midday));
    }
    if (evening.isNotEmpty) {
      widgets.add(_buildGroup('🌆 Evening', evening));
    }
    if (night.isNotEmpty) {
      widgets.add(_buildGroup('🌙 Night', night));
    }
    return widgets;
  }

  Widget _buildGroup(String title, List<Supplement> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title,
                style: const TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E1E35)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, color: Color(0xFF1E1E35), indent: 16, endIndent: 16),
                  _buildSupplementRow(items[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplementRow(Supplement s) {
    final taken = _takenToday.contains(s.id);
    final adherence = _adherence[s.id] ?? 0;
    return InkWell(
      onTap: () => _toggleTaken(s),
      onLongPress: () => _editSupplement(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Checkmark circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: taken
                    ? const Color(0xFF2ECC71)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: taken
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFF444466),
                  width: 2,
                ),
              ),
              child: taken
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s.name,
                            style: TextStyle(
                                color: taken
                                    ? const Color(0xFF888899)
                                    : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: taken
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: const Color(0xFF888899))),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D1A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(s.timeHhmm,
                            style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (s.dose != null && s.dose!.isNotEmpty) s.dose!,
                      '$adherence/7 days this week',
                    ].join(' · '),
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.more_vert_rounded,
                color: Color(0xFF444466), size: 16),
          ],
        ),
      ),
    );
  }
}

class _SupplementEditorSheet extends StatefulWidget {
  final Supplement? existing;
  const _SupplementEditorSheet({this.existing});

  @override
  State<_SupplementEditorSheet> createState() =>
      _SupplementEditorSheetState();
}

class _SupplementEditorSheetState extends State<_SupplementEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _doseCtrl;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _doseCtrl = TextEditingController(text: e?.dose ?? '');
    if (e != null) {
      final parts = e.timeHhmm.split(':');
      _time = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } else {
      _time = const TimeOfDay(hour: 8, minute: 0);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _doseCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
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
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final s = Supplement(
      id: widget.existing?.id,
      name: name,
      dose: _doseCtrl.text.trim().isEmpty ? null : _doseCtrl.text.trim(),
      timeHhmm: _fmt(_time),
    );
    popAfterFocusSettles(context, s);
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
            Text(widget.existing == null ? 'Add supplement' : 'Edit supplement',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            _sectionLabel('Name'),
            TextField(
              controller: _nameCtrl,
              autofocus: widget.existing == null,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('e.g. Thyrox, Creatine, D3+K2'),
            ),
            const SizedBox(height: 14),
            _sectionLabel('Dose (optional)'),
            TextField(
              controller: _doseCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('e.g. 75 mcg, 5 g, 1 softgel'),
            ),
            const SizedBox(height: 14),
            _sectionLabel('Time'),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A2A45)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: Color(0xFFFFD700), size: 18),
                    const SizedBox(width: 10),
                    Text(_fmt(_time),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    const Text('Daily reminder',
                        style: TextStyle(
                            color: Color(0xFF888899), fontSize: 12)),
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
                child: Text(
                    widget.existing == null ? 'Add' : 'Save',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
