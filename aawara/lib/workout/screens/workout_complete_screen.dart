import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';

class WorkoutCompleteScreen extends StatefulWidget {
  final WorkoutLog log;
  final Map<String, Exercise> exercises;
  final int elapsedSeconds;

  const WorkoutCompleteScreen({
    super.key,
    required this.log,
    required this.exercises,
    required this.elapsedSeconds,
  });

  @override
  State<WorkoutCompleteScreen> createState() => _WorkoutCompleteScreenState();
}

class _WorkoutCompleteScreenState extends State<WorkoutCompleteScreen>
    with SingleTickerProviderStateMixin {
  final _db = WorkoutDatabase.instance;
  final _screenshotKey = GlobalKey();
  final _scrollController = ScrollController();

  int _mood = 3;
  _PRRecord? _pr;
  bool _prChecked = false;
  bool _sharing = false;

  late final AnimationController _anim;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scale = CurvedAnimation(parent: _anim, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _detectPR();
  }

  @override
  void dispose() {
    _anim.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _shareScreenshot() async {
    setState(() => _sharing = true);
    try {
      // Scroll to top so the screenshot shows the full summary from the start
      await _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      // Wait for the frame to settle after scroll
      await Future.delayed(const Duration(milliseconds: 350));

      final boundary = _screenshotKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/aawara_${widget.log.workoutName.replaceAll(' ', '_')}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject:
            '${widget.log.workoutName} — ${_durationStr} · ${_fmtVol(widget.log.totalVolume)} kg',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not share: $e'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _detectPR() async {
    for (final exLog in widget.log.exercises) {
      final ex = widget.exercises[exLog.id];
      if (ex == null || exLog.sets.isEmpty) continue;

      final currentBest = exLog.sets
          .where((s) => s.weight != null && s.reps != null && s.reps! > 0)
          .fold<double>(0.0, (best, s) {
        final w = s.weight!;
        return w > best ? w : best;
      });

      if (currentBest == 0) continue;

      final prev = await _db.getLastSetsForExercise(exLog.exerciseId);
      if (prev.isEmpty) continue;

      final prevBest = prev
          .where((s) => s.weight != null)
          .fold<double>(0.0, (best, s) {
        final w = s.weight!;
        return w > best ? w : best;
      });

      if (currentBest > prevBest && prevBest > 0) {
        if (mounted) {
          setState(() {
            _pr = _PRRecord(
              exerciseName: ex.name,
              weight: currentBest,
              prevWeight: prevBest,
            );
            _prChecked = true;
          });
        }
        return;
      }
    }
    if (mounted) setState(() => _prChecked = true);
  }

  String get _durationStr {
    final m = widget.elapsedSeconds ~/ 60;
    final s = widget.elapsedSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int get _estCalories => ((widget.log.totalSets * 4.5)).round();

  String _fmtVol(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}k';
    }
    return v.toStringAsFixed(0);
  }

  List<MapEntry<String, double>> get _muscleSplit {
    final map = <String, double>{};
    for (final exLog in widget.log.exercises) {
      final ex = widget.exercises[exLog.id];
      if (ex == null) continue;
      map[ex.muscleGroup] = (map[ex.muscleGroup] ?? 0) + exLog.totalVolume;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: RepaintBoundary(
        key: _screenshotKey,
        child: Stack(
        children: [
          // Radial gold glow at top
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 320,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Color(0x30FFD700),
                    Color(0x00FFD700),
                  ],
                  radius: 0.7,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTrophy(),
                        const SizedBox(height: 20),
                        _buildStatsGrid(),
                        if (_prChecked && _pr != null) ...[
                          const SizedBox(height: 14),
                          _buildPRCard(),
                        ],
                        const SizedBox(height: 14),
                        _buildMuscleSplit(),
                        const SizedBox(height: 14),
                        _buildMoodPicker(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTrophy() {
    return Column(
      children: [
        const SizedBox(height: 16),
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD700), Color(0xFFB07A2C)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Color(0xFF2A1A06),
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FadeTransition(
          opacity: _fade,
          child: Column(
            children: [
              const Text(
                'Workout Complete!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Great job — you crushed this one.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      _StatData(
          value: _durationStr,
          label: 'Duration',
          icon: Icons.timer_outlined,
          color: const Color(0xFFFFD700)),
      _StatData(
          value: '$_estCalories',
          sub: 'kcal',
          label: 'Calories',
          icon: Icons.local_fire_department_rounded,
          color: const Color(0xFFF97316)),
      _StatData(
          value: _fmtVol(widget.log.totalVolume),
          sub: 'kg',
          label: 'Volume',
          icon: Icons.fitness_center_rounded,
          color: const Color(0xFFFFD700)),
      _StatData(
          value: '${widget.log.totalSets}',
          label: 'Total Sets',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF60A5FA)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: stats.map((s) => _buildStatCard(s)).toList(),
    );
  }

  Widget _buildStatCard(_StatData s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(s.icon, color: s.color, size: 16),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                s.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (s.sub != null) ...[
                const SizedBox(width: 4),
                Text(
                  s.sub!,
                  style: const TextStyle(
                      color: Color(0xFF6E6E78), fontSize: 11),
                ),
              ],
            ],
          ),
          Text(
            s.label,
            style: const TextStyle(color: Color(0xFF6E6E78), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPRCard() {
    final pr = _pr!;
    final diff = pr.weight - pr.prevWeight;
    final diffStr =
        '+${diff == diff.truncateToDouble() ? diff.toInt().toString() : diff.toStringAsFixed(1)} kg';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x30D4A055), Color(0x0AD4A055)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4A055).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Color(0xFF2A1A06), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEW PERSONAL RECORD',
                  style: TextStyle(
                    color: Color(0xFFD4A055),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${pr.exerciseName} · ${pr.weight == pr.weight.truncateToDouble() ? pr.weight.toInt() : pr.weight} kg',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$diffStr from last PR',
                  style: const TextStyle(
                      color: Color(0xFFA8A8B3), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuscleSplit() {
    final split = _muscleSplit;
    if (split.isEmpty) return const SizedBox.shrink();

    final maxVol = split.first.value;
    final colors = [
      const Color(0xFFFFD700),
      const Color(0xFFF97316),
      const Color(0xFF60A5FA),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Muscle Volume Split',
            style: TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...split.asMap().entries.map((entry) {
            final i = entry.key;
            final muscle = entry.value.key;
            final vol = entry.value.value;
            final pct = maxVol > 0 ? vol / maxVol : 0.0;
            final color = colors[i % colors.length];
            return Padding(
              padding: EdgeInsets.only(bottom: i < split.length - 1 ? 14 : 0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(muscle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${vol.toStringAsFixed(0)} kg',
                        style: const TextStyle(
                            color: Color(0xFFA8A8B3), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFF26262D),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMoodPicker() {
    const moods = ['😩', '😐', '🙂', '💪', '🔥'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW DID IT FEEL?',
            style: TextStyle(
              color: Color(0xFF6E6E78),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: moods.asMap().entries.map((entry) {
              final i = entry.key;
              final emoji = entry.value;
              final selected = i == _mood;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _mood = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i < 4 ? 8 : 0),
                    height: 48,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                          : const Color(0xFF1C1C21),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                            : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Text(emoji,
                          style: TextStyle(
                              fontSize: selected ? 24 : 20)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0D0D1A).withValues(alpha: 0),
            const Color(0xFF0D0D1A),
            const Color(0xFF0D0D1A),
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      child: Row(
        children: [
          // Share button
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: _sharing ? null : _shareScreenshot,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF333355)),
                ),
                child: _sharing
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFA8A8B3)),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded,
                              color: Color(0xFFA8A8B3), size: 18),
                          SizedBox(width: 8),
                          Text('Share',
                              style: TextStyle(
                                  color: Color(0xFFA8A8B3),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Add Session button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, 'add_session'),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF3498DB).withValues(alpha: 0.5)),
                  color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Color(0xFF3498DB), size: 18),
                    SizedBox(width: 6),
                    Text('Add Session',
                        style: TextStyle(
                            color: Color(0xFF3498DB),
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Done button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text(
                    'Done',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatData {
  final String value;
  final String? sub;
  final String label;
  final IconData icon;
  final Color color;

  const _StatData({
    required this.value,
    this.sub,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _PRRecord {
  final String exerciseName;
  final double weight;
  final double prevWeight;

  const _PRRecord({
    required this.exerciseName,
    required this.weight,
    required this.prevWeight,
  });
}
