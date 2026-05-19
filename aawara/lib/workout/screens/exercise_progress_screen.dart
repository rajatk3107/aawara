import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../widgets/muscle_group_filter.dart';
import 'exercise_progress_detail_screen.dart';

// ─── Color palette per muscle group ──────────────────────────────────────────

Color exerciseColor(String muscleGroup) => switch (muscleGroup) {
      'Chest' => const Color(0xFFFFD700),
      'Back' => const Color(0xFFA78BFA),
      'Legs' => const Color(0xFFF97316),
      'Shoulders' => const Color(0xFF60A5FA),
      'Arms' => const Color(0xFFF472B6),
      'Core' => const Color(0xFF3DD4C0),
      'Cardio' => const Color(0xFF4ADE80),
      _ => const Color(0xFFFFD700),
    };

// ─── Screen ───────────────────────────────────────────────────────────────────

class ExerciseProgressScreen extends StatefulWidget {
  const ExerciseProgressScreen({super.key});

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  final _db = WorkoutDatabase.instance;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _filterGroup; // null = All

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _db.getTrackedExerciseSummaries();
    if (mounted) {
      setState(() {
        _all = data;
        _applyFilter();
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    if (_filterGroup == null) {
      _filtered = _all;
    } else {
      _filtered = _all.where((e) {
        final ex = e['exercise'] as Exercise;
        return ex.muscleGroup == _filterGroup;
      }).toList();
    }
  }

  double get _totalGain =>
      _all.fold(0.0, (s, e) => s + (e['gain'] as double));

  int get _weeksTracked {
    if (_all.isEmpty) return 0;
    final dates = _all
        .map((e) => DateTime.tryParse(e['last_date'] as String))
        .whereType<DateTime>();
    if (dates.isEmpty) return 0;
    final latest = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final earliest = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    return ((latest.difference(earliest).inDays) / 7).ceil().clamp(1, 999);
  }

  Future<void> _openExercisePicker() async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExercisePickerSheet(),
    );
    if (picked == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseProgressDetailScreen(exercise: picked),
      ),
    ).then((_) => _load());
  }

  String _fmtGain(double g) {
    if (g <= 0) return '0 kg';
    return '+${g == g.truncateToDouble() ? g.toInt() : g.toStringAsFixed(1)} kg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Exercise Progress',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : RefreshIndicator(
              color: const Color(0xFFFFD700),
              backgroundColor: const Color(0xFF1A1A2E),
              onRefresh: _load,
              child: _all.isEmpty ? _buildEmpty() : _buildContent(),
            ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.show_chart_rounded,
            color: Color(0xFF333355), size: 64),
        const SizedBox(height: 16),
        const Text(
          'No exercise data yet',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Complete workouts and log sets to see\nyour progress tracked here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF888899), fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        const SizedBox(height: 4),
        _buildOverviewTile(),
        const SizedBox(height: 16),
        // Muscle group filter
        MuscleGroupFilter(
          selected: _filterGroup,
          onChanged: (g) => setState(() {
            _filterGroup = g;
            _applyFilter();
          }),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                'TRACKED EXERCISES · ${_filtered.length}',
                style: const TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        ..._filtered.map((data) => _ExerciseCard(
              data: data,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExerciseProgressDetailScreen(
                    exercise: data['exercise'] as Exercise,
                  ),
                ),
              ).then((_) => _load()),
            )),
        const SizedBox(height: 12),
        // Track another exercise
        GestureDetector(
          onTap: _openExercisePicker,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                  style: BorderStyle.solid),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: Color(0xFFFFD700), size: 18),
                SizedBox(width: 8),
                Text(
                  'Track another exercise',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTile() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x18FFD700), Color(0x04FFD700)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STRENGTH OVERVIEW',
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmtGain(_totalGain),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'total PR gains',
                style: TextStyle(color: Color(0xFF888899), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 5),
              Text(
                '${_all.length} exercises tracked',
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 12),
              ),
              const SizedBox(width: 16),
              const Icon(Icons.calendar_today_rounded,
                  color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 5),
              Text(
                '$_weeksTracked weeks',
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Exercise card with sparkline ─────────────────────────────────────────────

class _ExerciseCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _ExerciseCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ex = data['exercise'] as Exercise;
    final pr = data['pr'] as double;
    final last = data['last_weight'] as double;
    final gain = data['gain'] as double;
    final sparks = (data['sparkline'] as List).cast<double>();
    final color = exerciseColor(ex.muscleGroup);

    String fmtW(double w) =>
        w == w.truncateToDouble() ? w.toInt().toString() : w.toStringAsFixed(1);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Icon
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.fitness_center_rounded,
                      color: color, size: 20),
                ),
                const SizedBox(width: 12),
                // Name + muscle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            ex.muscleGroup,
                            style: const TextStyle(
                                color: Color(0xFF888899), fontSize: 11),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF888899),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Last: ${fmtW(last)} kg',
                            style: const TextStyle(
                                color: Color(0xFF888899), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // PR + gain
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: fmtW(pr),
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(
                            text: ' kg',
                            style: TextStyle(
                                color: Color(0xFF888899), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          gain > 0
                              ? Icons.trending_up_rounded
                              : Icons.remove_rounded,
                          color: gain > 0
                              ? const Color(0xFF2ECC71)
                              : const Color(0xFF888899),
                          size: 11,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          gain > 0
                              ? '+${fmtW(gain)} kg'
                              : '0 kg',
                          style: TextStyle(
                            color: gain > 0
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFF888899),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            // Sparkline
            if (sparks.length > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    '9 WK',
                    style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: CustomPaint(
                        painter: _SparklinePainter(sparks, color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xFF555577), size: 16),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Sparkline painter ────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _SparklinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final mn = values.reduce(math.min);
    final mx = values.reduce(math.max);
    final range = (mx - mn).clamp(1.0, double.infinity);

    double sx(int i) => i / (values.length - 1) * size.width;
    double sy(double v) => size.height - ((v - mn) / range) * (size.height - 4) - 2;

    final pts = List.generate(values.length, (i) => Offset(sx(i), sy(values[i])));

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      final cp1 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i - 1].dy);
      final cp2 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i].dx, pts[i].dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      pts.last,
      3.0,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

// ─── Exercise picker bottom sheet ─────────────────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _db = WorkoutDatabase.instance;
  final _ctrl = TextEditingController();
  List<Exercise> _all = [];
  List<Exercise> _filtered = [];
  String? _group;

  @override
  void initState() {
    super.initState();
    _db.getAllExercises().then((list) {
      if (mounted) {
        setState(() {
          _all = list;
          _filtered = list;
        });
      }
    });
    _ctrl.addListener(_filter);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter() {
    final q = _ctrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((e) {
        final mq = e.name.toLowerCase().contains(q);
        final mg = _group == null || e.muscleGroup == _group;
        return mq && mg;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, sc) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF444466),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Text('Select Exercise',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF888899))),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: const TextStyle(color: Color(0xFF444466)),
                  prefixIcon:
                      const Icon(Icons.search, color: Color(0xFF888899)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            MuscleGroupFilter(
              selected: _group,
              onChanged: (g) => setState(() {
                _group = g;
                _filter();
              }),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Color(0xFF1A1A2E), height: 1),
                itemBuilder: (_, i) {
                  final ex = _filtered[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: exerciseColor(ex.muscleGroup)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.fitness_center_rounded,
                          color: exerciseColor(ex.muscleGroup), size: 16),
                    ),
                    title: Text(ex.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text(
                        '${ex.muscleGroup} · ${ex.equipment}',
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, ex),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
