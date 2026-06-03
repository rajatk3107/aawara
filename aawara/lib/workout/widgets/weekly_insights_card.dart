import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/workout_database.dart';
import '../models/workout_log.dart';
import '../../nutrition/models/nutrition_models.dart';

/// Compact summary card showing this-week vs last-week comparisons:
/// - Training days (target = workouts/week goal)
/// - Sets per muscle group
/// - Avg daily protein and calories
/// - Avg daily water
/// Designed to live at the top of the Progress > Strength tab.
class WeeklyInsightsCard extends StatefulWidget {
  const WeeklyInsightsCard({super.key});

  @override
  State<WeeklyInsightsCard> createState() => _WeeklyInsightsCardState();
}

class _WeeklyInsightsCardState extends State<WeeklyInsightsCard> {
  final _db = WorkoutDatabase.instance;

  WeeklyInsights? _thisWeek;
  WeeklyInsights? _lastWeek;
  NutritionGoals _goals = NutritionGoals.defaults;
  int _weeklyTargetDays = 5;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    final thisSunday = thisMonday.add(const Duration(days: 6));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final lastSunday = thisMonday.subtract(const Duration(days: 1));

    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait([
      _db.getWeeklyInsights(
          fromDate: _fmt(thisMonday), toDate: _fmt(thisSunday)),
      _db.getWeeklyInsights(
          fromDate: _fmt(lastMonday), toDate: _fmt(lastSunday)),
      _db.getNutritionGoals(),
    ]);
    if (!mounted) return;
    setState(() {
      _thisWeek = results[0] as WeeklyInsights;
      _lastWeek = results[1] as WeeklyInsights;
      _goals = (results[2] as NutritionGoals?) ?? NutritionGoals.defaults;
      _weeklyTargetDays = prefs.getInt('weekly_workout_target') ?? 5;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _thisWeek == null) {
      return const SizedBox.shrink();
    }
    final tw = _thisWeek!;
    final lw = _lastWeek!;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              const Icon(Icons.insights_rounded,
                  color: Color(0xFFFFD700), size: 16),
              const SizedBox(width: 6),
              const Text('THIS WEEK',
                  style: TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          // Top row: training days, protein, calories, water
          Row(
            children: [
              _stat(
                'Training',
                '${tw.trainingDays}/$_weeklyTargetDays',
                'days',
                color: tw.trainingDays >= _weeklyTargetDays
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFFFFD700),
                delta: tw.trainingDays - lw.trainingDays,
                deltaUnit: '',
              ),
              _divider(),
              _stat(
                'Protein',
                '${tw.avgProteinG.round()}',
                'g/day',
                color: tw.avgProteinG >= _goals.proteinG
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFF3498DB),
                delta: (tw.avgProteinG - lw.avgProteinG).round(),
                deltaUnit: 'g',
              ),
              _divider(),
              _stat(
                'Calories',
                '${tw.avgCalories.round()}',
                'kcal/day',
                color: Colors.white,
                delta: (tw.avgCalories - lw.avgCalories).round(),
                deltaUnit: '',
              ),
              _divider(),
              _stat(
                'Water',
                '${tw.avgGlassesWater.toStringAsFixed(1)}',
                'glasses',
                color: const Color(0xFF4FC3F7),
                delta: ((tw.avgGlassesWater - lw.avgGlassesWater) * 10).round(),
                deltaUnit: '',
                // Show one-decimal delta — multiply by 10 above, divide by 10 below
                deltaTransform: (n) => (n / 10).toStringAsFixed(1),
              ),
            ],
          ),
          if (tw.setsPerMuscleGroup.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF1E1E35), height: 1),
            const SizedBox(height: 12),
            const Text('SETS BY MUSCLE GROUP',
                style: TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _sortedMuscleGroups(tw.setsPerMuscleGroup)
                  .map((e) => _muscleChip(e.key, e.value))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _sortedMuscleGroups(Map<String, int> map) {
    final list = map.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  Widget _muscleChip(String group, int sets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A45)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 12),
          children: [
            TextSpan(text: '$group '),
            TextSpan(
                text: '$sets',
                style: const TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0xFF1E1E35),
      );

  Widget _stat(
    String label,
    String value,
    String unit, {
    required Color color,
    required int delta,
    required String deltaUnit,
    String Function(int)? deltaTransform,
  }) {
    final showDelta = delta != 0;
    final positive = delta > 0;
    final deltaText =
        deltaTransform != null ? deltaTransform(delta.abs()) : delta.abs().toString();
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF888899), fontSize: 10)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(unit,
              style: const TextStyle(color: Color(0xFF555577), fontSize: 9)),
          if (showDelta) ...[
            const SizedBox(height: 2),
            Text(
              '${positive ? '↑' : '↓'}$deltaText$deltaUnit',
              style: TextStyle(
                  color: positive
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFFE74C3C),
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
