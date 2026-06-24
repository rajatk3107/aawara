import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/workout_heatmap.dart';
import '../widgets/weekly_insights_card.dart';
import 'body_measurements_screen.dart';
import 'exercise_progress_screen.dart';
import 'progress_photos_screen.dart';
import 'one_rep_max_calculator_screen.dart';
import 'step_goal_screen.dart';
import '../widgets/plateau_banner.dart';
import '../../nutrition/models/nutrition_models.dart';
import '../../app_refresh.dart';

enum _Interval { all, twoWeeks, oneMonth, threeMonths, sixMonths, custom }

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin
    implements RefreshableState {
  final _db = WorkoutDatabase.instance;

  @override
  void refreshData() {
    if (mounted) _load(silent: true);
  }
  late TabController _tabCtrl;

  // Strength tab
  List<Exercise> _exercises = [];
  Exercise? _selected;
  List<Map<String, dynamic>> _progressData = [];
  Map<String, dynamic>? _pr;
  bool _chartLoading = false;
  _Interval _interval = _Interval.all;
  DateTime? _customFrom;
  DateTime? _customTo;

  // Body weight tab
  List<Map<String, dynamic>> _weightData = [];
  List<Map<String, dynamic>> _wellnessData = [];
  bool _weightLoading = false;
  _Interval _weightInterval = _Interval.all;
  DateTime? _weightCustomFrom;
  DateTime? _weightCustomTo;

  // Nutrition tab
  List<DailyNutritionSummary> _nutritionHistory = [];
  NutritionGoals _nutGoals = NutritionGoals.defaults;
  bool _nutritionLoading = false;

  // Step history
  List<Map<String, dynamic>> _stepHistory = [];
  int _stepGoal = 8000;
  bool _stepHistoryLoaded = false;
  int? _stepTouchedIndex;

  // Heatmap
  int _heatmapMonths = 6;

  // Shared overview
  int _streak = 0;
  int _weeklyCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && _weightData.isEmpty && !_weightLoading) {
        _loadWeightData();
      }
      if (_tabCtrl.index == 2 && _nutritionHistory.isEmpty && !_nutritionLoading) {
        _loadNutritionData();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final exercises = await _db.getAllExercises();
    final streak = await _db.getWorkoutStreak();
    final weekly = await _db.getWeeklyWorkoutCount();
    if (mounted) {
      setState(() {
        _exercises = exercises;
        _streak = streak;
        _weeklyCount = weekly;
        _loading = false;
      });
    }
    // Only auto-select on first load; don't override the user's chosen exercise
    // when silently refreshing.
    if (exercises.isNotEmpty && _selected == null) {
      _selectExercise(exercises.first);
    }
    _loadWeightData(silent: silent);
    _loadStepHistory();
  }

  Future<void> _loadStepHistory() async {
    final rows = await _db.getStepHistory(7);
    final prefs = await SharedPreferences.getInstance();
    final goal = prefs.getInt('step_goal') ?? 8000;
    if (mounted) {
      setState(() {
        _stepHistory = rows;
        _stepGoal = goal;
        _stepHistoryLoaded = true;
      });
    }
  }

  Future<void> _loadWeightData({bool silent = false}) async {
    if (!silent) setState(() => _weightLoading = true);
    final results = await Future.wait([
      _db.getBodyWeightLogs(
          fromDate: _weightFromDate(), toDate: _weightToDate()),
      _db.getWellnessLogs(
          fromDate: _weightFromDate(), toDate: _weightToDate()),
    ]);
    if (mounted) {
      setState(() {
        _weightData = results[0];
        _wellnessData = results[1];
        _weightLoading = false;
      });
    }
  }

  String? _weightFromDate() {
    final now = DateTime.now();
    switch (_weightInterval) {
      case _Interval.twoWeeks:
        return _fmt(now.subtract(const Duration(days: 14)));
      case _Interval.oneMonth:
        return _fmt(now.subtract(const Duration(days: 30)));
      case _Interval.threeMonths:
        return _fmt(now.subtract(const Duration(days: 90)));
      case _Interval.sixMonths:
        return _fmt(now.subtract(const Duration(days: 180)));
      case _Interval.custom:
        return _weightCustomFrom != null ? _fmt(_weightCustomFrom!) : null;
      default:
        return null;
    }
  }

  String? _weightToDate() {
    if (_weightInterval == _Interval.custom && _weightCustomTo != null) {
      return _fmt(_weightCustomTo!);
    }
    return null;
  }

  Future<void> _setWeightInterval(_Interval i) async {
    if (i == _Interval.custom) {
      final range = await showDateRangePicker(
        context: context,
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
      if (range == null) return;
      _weightCustomFrom = range.start;
      _weightCustomTo = range.end;
    }
    setState(() => _weightInterval = i);
    _loadWeightData();
  }

  String? _fromDate() {
    final now = DateTime.now();
    switch (_interval) {
      case _Interval.twoWeeks:
        return _fmt(now.subtract(const Duration(days: 14)));
      case _Interval.oneMonth:
        return _fmt(now.subtract(const Duration(days: 30)));
      case _Interval.threeMonths:
        return _fmt(now.subtract(const Duration(days: 90)));
      case _Interval.sixMonths:
        return _fmt(now.subtract(const Duration(days: 180)));
      case _Interval.custom:
        return _customFrom != null ? _fmt(_customFrom!) : null;
      default:
        return null;
    }
  }

  String? _toDate() {
    if (_interval == _Interval.custom && _customTo != null) {
      return _fmt(_customTo!);
    }
    return null;
  }

  Future<void> _selectExercise(Exercise ex) async {
    setState(() {
      _selected = ex;
      _chartLoading = true;
    });
    final data = await _db.getProgressForExercise(ex.id,
        fromDate: _fromDate(), toDate: _toDate());
    final pr = await _db.getPRForExercise(ex.id);
    if (mounted) {
      setState(() {
        _progressData = data;
        _pr = pr;
        _chartLoading = false;
      });
    }
  }

  Future<void> _setInterval(_Interval i) async {
    if (i == _Interval.custom) {
      final range = await showDateRangePicker(
        context: context,
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
      if (range == null) return;
      _customFrom = range.start;
      _customTo = range.end;
    }
    setState(() => _interval = i);
    if (_selected != null) _selectExercise(_selected!);
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('Progress',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: const Color(0xFF555577),
          indicatorColor: const Color(0xFFFFD700),
          indicatorWeight: 2,
          tabs: const [
            Tab(text: 'Strength'),
            Tab(text: 'Body'),
            Tab(text: 'Nutrition'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildStrengthTab(),
                _buildBodyWeightTab(),
                _buildNutritionTab(),
              ],
            ),
    );
  }

  Widget _buildStrengthTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const WeeklyInsightsCard(),
        const SizedBox(height: 16),
        _buildOverviewCards(),
        const SizedBox(height: 16),
        _buildExerciseTrackerBanner(),
        const SizedBox(height: 10),
        _buildProgressPhotosBanner(),
        const SizedBox(height: 10),
        _build1RMCalculatorBanner(),
        const SizedBox(height: 20),
        _buildSectionHeader('Activity'),
        const SizedBox(height: 8),
        _buildHeatmapFilterChips(),
        const SizedBox(height: 8),
        WorkoutHeatmap(months: _heatmapMonths),
        const SizedBox(height: 16),
        const PlateauBanner(),
        _buildSectionHeader('Strength Progress'),
        const SizedBox(height: 12),
        _buildExercisePicker(),
        const SizedBox(height: 12),
        _buildIntervalChips(),
        const SizedBox(height: 16),
        _buildChart(),
        if (_pr != null) ...[
          const SizedBox(height: 16),
          _buildPRCard(),
        ],
        if (_progressData.length > 1) ...[
          const SizedBox(height: 24),
          _buildSectionHeader('Session Detail'),
          const SizedBox(height: 12),
          _buildProgressDetail(),
        ],
        const SizedBox(height: 28),
        _buildSectionHeader('Daily Steps'),
        const SizedBox(height: 12),
        _buildStepHistorySection(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildStepHistorySection() {
    if (!_stepHistoryLoaded) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(
              color: Color(0xFFFFD700), strokeWidth: 2),
        ),
      );
    }
    if (_stepHistory.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.directions_walk_rounded,
        title: 'No step data yet',
        subtitle: 'Enable step tracking in Settings to start '
            'seeing your daily activity here.',
      );
    }

    // Build a 7-day window (fill missing days with 0)
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final byDate = {for (final r in _stepHistory) r['date'] as String: r};

    final stepValues = days.map((d) {
      final r = byDate[d];
      return r != null ? (r['steps'] as num).toInt() : 0;
    }).toList();

    final maxSteps =
        stepValues.reduce((a, b) => a > b ? a : b).toDouble();
    final chartMax =
        (maxSteps > _stepGoal ? maxSteps * 1.2 : _stepGoal * 1.2)
            .ceilToDouble();

    // Summary stats
    final nonZero = stepValues.where((s) => s > 0).toList();
    final avg = nonZero.isEmpty
        ? 0
        : (nonZero.reduce((a, b) => a + b) / nonZero.length).round();
    final best = stepValues.reduce((a, b) => a > b ? a : b);
    final goalMet = stepValues.where((s) => s >= _stepGoal).length;

    Color barColor(int steps) {
      if (_stepGoal <= 0) return const Color(0xFFFFD700);
      final pct = steps / _stepGoal;
      if (pct >= 1.0) return const Color(0xFFFFD700);
      if (pct >= 0.75) return const Color(0xFFFFD700).withValues(alpha: 0.6);
      if (pct >= 0.5) return const Color(0xFFFFD700).withValues(alpha: 0.35);
      return const Color(0xFF2A2A3E);
    }

    String fmtK(int n) {
      if (n >= 1000) {
        final k = (n / 1000).toStringAsFixed(1);
        return '${k}k';
      }
      return n.toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMax,
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  if (event is FlTapUpEvent) {
                    setState(() {
                      final idx = response?.spot?.touchedBarGroupIndex;
                      _stepTouchedIndex =
                          _stepTouchedIndex == idx ? null : idx;
                    });
                  }
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1A1A2E),
                  tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  getTooltipItem: (group, _, rod, __) {
                    final steps = rod.toY.round();
                    final pct = _stepGoal > 0
                        ? (steps / _stepGoal * 100).round()
                        : 0;
                    final dist = (steps * 0.000762).toStringAsFixed(1);
                    final cal = (steps * 0.038).round();
                    return BarTooltipItem(
                      '${fmtK(steps)} steps\n$pct% · ~$dist km · ~$cal kcal',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.5),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= days.length) {
                        return const SizedBox.shrink();
                      }
                      final d = DateTime.parse(days[idx]);
                      return Text(
                        dayLabels[d.weekday - 1],
                        style: const TextStyle(
                            color: Color(0xFF444466), fontSize: 9),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: Color(0xFF1E1E35), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: _stepGoal.toDouble(),
                  color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                  strokeWidth: 1.5,
                  dashArray: [4, 4],
                ),
              ]),
              barGroups: List.generate(7, (i) {
                final steps = stepValues[i];
                final isSelected = _stepTouchedIndex == i;
                return BarChartGroupData(
                  x: i,
                  showingTooltipIndicators:
                      isSelected && steps > 0 ? [0] : [],
                  barRods: [
                    BarChartRodData(
                      toY: steps > 0 ? steps.toDouble() : 0,
                      width: 18,
                      borderRadius: BorderRadius.circular(4),
                      color: steps > 0
                          ? barColor(steps)
                          : const Color(0xFF1E1E35),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _stepChip('Avg', fmtK(avg)),
            const SizedBox(width: 8),
            _stepChip('Best', fmtK(best)),
            const SizedBox(width: 8),
            _stepChip('Goal met', '$goalMet/7'),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final result = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const StepGoalScreen(isFirstSetup: false)),
                );
                if (result != null) _loadStepHistory();
              },
              child: const Text('Change goal ›',
                  style: TextStyle(color: Color(0xFF555577), fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: Color(0xFF555577), fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildExerciseTrackerBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExerciseProgressScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1800), Color(0xFF1A1A2E)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.show_chart_rounded,
                  color: Color(0xFFFFD700), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Exercise Tracker',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('PRs, trends & session history per exercise',
                      style: TextStyle(
                          color: Color(0xFF888899), fontSize: 12)),
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

  Widget _buildProgressPhotosBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProgressPhotosScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF3498DB).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFF3498DB), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress Photos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Track your physique over time',
                      style: TextStyle(
                          color: Color(0xFF888899), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF3498DB), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _build1RMCalculatorBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OneRepMaxCalculatorScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calculate_rounded,
                  color: Color(0xFF2ECC71), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1RM Calculator',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Estimate your max & rep targets',
                      style: TextStyle(color: Color(0xFF888899), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF2ECC71), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementsBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BodyMeasurementsScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF8E44AD).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.straighten_rounded,
                  color: Color(0xFF8E44AD), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Body Measurements',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Track waist, chest, arms & more over time',
                      style: TextStyle(
                          color: Color(0xFF888899), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF8E44AD), size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyWeightTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildMeasurementsBanner(),
        const SizedBox(height: 12),
        _buildSectionHeader('Body Weight'),
        const SizedBox(height: 4),
        const Text('Track your daily weight over time',
            style: TextStyle(color: Color(0xFF555577), fontSize: 13)),
        const SizedBox(height: 16),
        _buildWeightIntervalChips(),
        const SizedBox(height: 16),
        _buildWeightChart(),
        if (_wellnessData.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Wellness Trends'),
          const SizedBox(height: 8),
          _buildWellnessChart(),
        ],
        if (_weightData.length > 1) ...[
          const SizedBox(height: 24),
          _buildSectionHeader('Weight Log'),
          const SizedBox(height: 12),
          ..._weightData.reversed.take(20).map((row) {
            final date = row['date'] as String;
            final wt = (row['weight_kg'] as num).toDouble();
            // Find matching wellness
            final w = _wellnessData.where((r) => r['date'] == date).firstOrNull;
            final energyEmojis = ['😴', '😕', '😐', '🙂', '⚡'];
            final energy = w != null ? (w['energy'] as int) : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monitor_weight_outlined,
                      color: Color(0xFF3498DB), size: 18),
                  const SizedBox(width: 12),
                  Text(_fmtDate(date),
                      style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  const Spacer(),
                  if (energy != null) ...[
                    Text(energyEmojis[energy - 1],
                        style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                  ],
                  Text('${wt.toStringAsFixed(1)} kg',
                      style: const TextStyle(
                          color: Color(0xFF3498DB),
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildWellnessChart() {
    // Build date-indexed maps for energy and soreness
    final energyMap = <String, double>{};
    final sorenessMap = <String, double>{};
    for (final r in _wellnessData) {
      final date = r['date'] as String;
      energyMap[date] = (r['energy'] as int).toDouble();
      sorenessMap[date] = (r['soreness'] as int).toDouble();
    }

    // Use union of all dates (wellness only; weight dates add no new x-axis for this chart)
    final dates = _wellnessData.map((r) => r['date'] as String).toList()
      ..sort();
    if (dates.isEmpty) return const SizedBox.shrink();

    final energySpots = <FlSpot>[];
    final sorenessSpots = <FlSpot>[];
    final dateLabels = <double, String>{};

    for (int i = 0; i < dates.length; i++) {
      final d = dates[i];
      dateLabels[i.toDouble()] = d;
      if (energyMap.containsKey(d)) {
        energySpots.add(FlSpot(i.toDouble(), energyMap[d]!));
      }
      if (sorenessMap.containsKey(d)) {
        sorenessSpots.add(FlSpot(i.toDouble(), sorenessMap[d]!));
      }
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _wellnessLegendDot(const Color(0xFF2ECC71)),
              const SizedBox(width: 4),
              const Text('Energy', style: TextStyle(color: Color(0xFF888899), fontSize: 10)),
              const SizedBox(width: 12),
              _wellnessLegendDot(const Color(0xFFE74C3C)),
              const SizedBox(width: 4),
              const Text('Soreness', style: TextStyle(color: Color(0xFF888899), fontSize: 10)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (dates.length - 1).toDouble(),
                minY: 0.5,
                maxY: 5.5,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}',
                          style: const TextStyle(
                              color: Color(0xFF555577), fontSize: 9)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: dates.length > 5
                          ? (dates.length / 4).roundToDouble()
                          : 1,
                      getTitlesWidget: (v, _) {
                        final d = dateLabels[v];
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
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  if (energySpots.isNotEmpty)
                    LineChartBarData(
                      spots: energySpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: const Color(0xFF2ECC71),
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  if (sorenessSpots.isNotEmpty)
                    LineChartBarData(
                      spots: sorenessSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: const Color(0xFFE74C3C),
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wellnessLegendDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _buildWeightIntervalChips() {
    final chips = [
      (_Interval.all, 'All'),
      (_Interval.twoWeeks, '2W'),
      (_Interval.oneMonth, '1M'),
      (_Interval.threeMonths, '3M'),
      (_Interval.sixMonths, '6M'),
      (_Interval.custom, 'Custom'),
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: chips.map((c) {
          final selected = _weightInterval == c.$1;
          String label = c.$2;
          if (c.$1 == _Interval.custom &&
              _weightCustomFrom != null &&
              _weightCustomTo != null) {
            label =
                '${DateFormat('d/M').format(_weightCustomFrom!)}–${DateFormat('d/M').format(_weightCustomTo!)}';
          }
          return GestureDetector(
            onTap: () => _setWeightInterval(c.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF3498DB)
                    : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF3498DB)
                      : const Color(0xFF333355),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFFCCCCDD),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeightChart() {
    if (_weightLoading) {
      return const SizedBox(
          height: 220,
          child: Center(
              child: CircularProgressIndicator(color: Color(0xFF3498DB))));
    }
    if (_weightData.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const EmptyStateWidget(
          icon: Icons.monitor_weight_outlined,
          title: 'No weight entries yet',
          subtitle: 'Tap + to log today\'s weight and start tracking your trend',
        ),
      );
    }

    final spots = <FlSpot>[];
    final dates = <double, String>{};
    for (int i = 0; i < _weightData.length; i++) {
      final row = _weightData[i];
      spots.add(FlSpot(i.toDouble(), (row['weight_kg'] as num).toDouble()));
      dates[i.toDouble()] = row['date'] as String;
    }
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) < 2 ? 2.0 : (maxY - minY) * 0.2;

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
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
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF1E1E35), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(1)}',
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: spots.length > 6
                    ? (spots.length / 4).roundToDouble()
                    : 1,
                getTitlesWidget: (v, _) {
                  final date = dates[v];
                  if (date == null) return const SizedBox.shrink();
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('d/M').format(DateTime.parse(date)),
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 10),
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
              color: const Color(0xFF3498DB),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: const Color(0xFF3498DB),
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF0D0D1A),
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x333498DB), Color(0x003498DB)],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A2E),
              tooltipBorder: const BorderSide(color: Color(0xFF3498DB)),
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} kg\n',
                        const TextStyle(
                            color: Color(0xFF3498DB),
                            fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(
                            text: dates[s.x] ?? '',
                            style: const TextStyle(
                                color: Color(0xFF888899),
                                fontSize: 11,
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

  Widget _buildOverviewCards() => Row(
        children: [
          _OverviewCard(
            icon: Icons.local_fire_department,
            label: 'Current Streak',
            value: '$_streak days',
            color: const Color(0xFFFF6B35),
          ),
          const SizedBox(width: 12),
          _OverviewCard(
            icon: Icons.calendar_today,
            label: 'This Week',
            value: '$_weeklyCount workouts',
            color: const Color(0xFF3498DB),
          ),
        ],
      );

  Widget _buildExercisePicker() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF333355)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Exercise>(
            value: _selected,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A2E),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF888899)),
            items: _exercises
                .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                .toList(),
            onChanged: (e) {
              if (e != null) _selectExercise(e);
            },
          ),
        ),
      );

  Widget _buildHeatmapFilterChips() {
    final chips = [(1, '1M'), (3, '3M'), (6, '6M')];
    return Row(
      children: chips.map((c) {
        final selected = _heatmapMonths == c.$1;
        return GestureDetector(
          onTap: () => setState(() => _heatmapMonths = c.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF333355),
              ),
            ),
            child: Text(
              c.$2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : const Color(0xFFCCCCDD),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildIntervalChips() {
    final chips = [
      (_Interval.all, 'All'),
      (_Interval.twoWeeks, '2W'),
      (_Interval.oneMonth, '1M'),
      (_Interval.threeMonths, '3M'),
      (_Interval.sixMonths, '6M'),
      (_Interval.custom, 'Custom'),
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: chips.map((c) {
          final selected = _interval == c.$1;
          String label = c.$2;
          if (c.$1 == _Interval.custom && _customFrom != null && _customTo != null) {
            label =
                '${DateFormat('d/M').format(_customFrom!)}–${DateFormat('d/M').format(_customTo!)}';
          }
          return GestureDetector(
            onTap: () => _setInterval(c.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF333355),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.black : const Color(0xFFCCCCDD),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChart() {
    if (_chartLoading) {
      return const SizedBox(
        height: 220,
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFFFFD700))),
      );
    }
    if (_progressData.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const EmptyStateWidget(
          icon: Icons.bar_chart_rounded,
          title: 'Nothing to show yet',
          subtitle: 'Log a few workouts and your progress will appear here',
        ),
      );
    }

    final spots = <FlSpot>[];
    final dates = <double, String>{};
    for (int i = 0; i < _progressData.length; i++) {
      final row = _progressData[i];
      spots.add(FlSpot(i.toDouble(), (row['max_weight'] as num).toDouble()));
      dates[i.toDouble()] = row['date'] as String;
    }
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) < 5 ? 5.0 : (maxY - minY) * 0.15;

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
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
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0xFF333355), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text('${v.toInt()}kg',
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: spots.length > 6
                    ? (spots.length / 4).roundToDouble()
                    : 1,
                getTitlesWidget: (v, _) {
                  final date = dates[v];
                  if (date == null) return const SizedBox.shrink();
                  try {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('d/M').format(DateTime.parse(date)),
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 10),
                      ),
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: const Color(0xFFFFD700),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: const Color(0xFFFFD700),
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF0D0D1A),
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33FFD700), Color(0x00FFD700)],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1A1A2E),
              tooltipBorder:
                  const BorderSide(color: Color(0xFFFFD700)),
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} kg\n',
                        const TextStyle(
                            color: Color(0xFFFFD700),
                            fontWeight: FontWeight.bold),
                        children: [
                          TextSpan(
                            text: dates[s.x] ?? '',
                            style: const TextStyle(
                                color: Color(0xFF888899),
                                fontSize: 11,
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

  Widget _buildPRCard() {
    final pr = _pr!;
    final weight = (pr['weight'] as num).toDouble();
    final reps = pr['reps'] as int?;
    final date = pr['date'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(colors: [Color(0xFF2D1F00), Color(0xFF1A1A2E)]),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('PR',
                  style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personal Record',
                    style: TextStyle(color: Color(0xFF888899), fontSize: 12)),
                Text(
                  '${_fmtW(weight)} kg${reps != null ? ' × $reps reps' : ''}',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                if (date != null) Text(_fmtDate(date),
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 28),
        ],
      ),
    );
  }

  // ─── PROGRESS DETAIL ────────────────────────────────────────────────────────

  Widget _buildProgressDetail() {
    // Build from most-recent to oldest
    final entries = List.of(_progressData.reversed.toList());
    return Column(
      children: entries.asMap().entries.map((e) {
        final i = e.key;
        final row = e.value;
        final weight = (row['max_weight'] as num).toDouble();
        final date = row['date'] as String;

        // Compare to next entry (which is the previous session in reversed order)
        double? delta;
        if (i + 1 < entries.length) {
          final prevWeight =
              (entries[i + 1]['max_weight'] as num).toDouble();
          delta = weight - prevWeight;
        }

        return _ProgressDetailRow(
          date: date,
          weight: weight,
          delta: delta,
          isFirst: i == 0,
        );
      }).toList(),
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) => Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      );

  String _fmtW(double w) =>
      w == w.truncate() ? w.toInt().toString() : w.toStringAsFixed(1);

  String _fmtDate(String date) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

  // ─── Nutrition tab ────────────────────────────────────────────────────────

  Future<void> _loadNutritionData() async {
    setState(() => _nutritionLoading = true);
    final now = DateTime.now();
    final from = _fmt(now.subtract(const Duration(days: 29)));
    final to = _fmt(now);
    final results = await Future.wait([
      _db.getNutritionHistory(from, to),
      _db.getNutritionGoals(),
    ]);
    if (mounted) {
      setState(() {
        _nutritionHistory = results[0] as List<DailyNutritionSummary>;
        _nutGoals = (results[1] as NutritionGoals?) ?? NutritionGoals.defaults;
        _nutritionLoading = false;
      });
    }
  }

  Widget _buildNutritionTab() {
    if (_nutritionLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }
    if (_nutritionHistory.isEmpty) {
      return const Center(
        child: Text('No nutrition data yet.\nStart logging meals!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF555577), fontSize: 15)),
      );
    }

    final now = DateTime.now();
    final last7 = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return _fmt(d);
    });
    final byDate = {for (final s in _nutritionHistory) s.date: s};

    final logged7 = last7.where((d) => byDate.containsKey(d)).length.clamp(1, 7);
    final avg7Cal =
        last7.fold(0.0, (s, d) => s + (byDate[d]?.calories ?? 0)) / logged7;
    final avg7Prot =
        last7.fold(0.0, (s, d) => s + (byDate[d]?.proteinG ?? 0)) / logged7;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _nutAvgCard('Avg Calories', '${avg7Cal.round()} kcal',
                '/ ${_nutGoals.calories.round()}', const Color(0xFFFFD700)),
            const SizedBox(width: 10),
            _nutAvgCard('Avg Protein', '${avg7Prot.round()}g',
                '/ ${_nutGoals.proteinG.round()}g', const Color(0xFF3498DB)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Last 7 Days — Calories',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (_nutGoals.calories * 1.3).ceilToDouble(),
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= last7.length) return const SizedBox.shrink();
                      final parts = last7[idx].split('-');
                      return Text(
                        '${int.parse(parts[2])}/${int.parse(parts[1])}',
                        style: const TextStyle(color: Color(0xFF444466), fontSize: 9),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: Color(0xFF1E1E35), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: _nutGoals.calories,
                  color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ]),
              barGroups: last7.asMap().entries.map((e) {
                final idx = e.key;
                final s = byDate[e.value];
                final cal = s?.calories ?? 0;
                final prot = s?.proteinG ?? 0;
                final carbsV = s?.carbsG ?? 0;
                final fat = s?.fatG ?? 0;
                final total = prot * 4 + carbsV * 4 + fat * 9;
                return BarChartGroupData(
                  x: idx,
                  barRods: [
                    BarChartRodData(
                      toY: cal,
                      width: 22,
                      borderRadius: BorderRadius.circular(4),
                      rodStackItems: total > 0
                          ? [
                              BarChartRodStackItem(0, prot * 4, const Color(0xFF3498DB)),
                              BarChartRodStackItem(prot * 4, prot * 4 + carbsV * 4, const Color(0xFF2ECC71)),
                              BarChartRodStackItem(prot * 4 + carbsV * 4, prot * 4 + carbsV * 4 + fat * 9, const Color(0xFFE67E22)),
                            ]
                          : [BarChartRodStackItem(0, 0.1, const Color(0xFF1E1E35))],
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _nutLegend('Protein', const Color(0xFF3498DB)),
            const SizedBox(width: 16),
            _nutLegend('Carbs', const Color(0xFF2ECC71)),
            const SizedBox(width: 16),
            _nutLegend('Fat', const Color(0xFFE67E22)),
            const SizedBox(width: 16),
            _nutLegend('Goal', const Color(0xFFFFD700), dashed: true),
          ],
        ),
        const SizedBox(height: 24),
        const Text('30-Day Log',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ..._nutritionHistory.reversed.take(14).map(_buildNutRow),
      ],
    );
  }

  Widget _nutAvgCard(String label, String value, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF888899), fontSize: 12)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(sub,
                style: const TextStyle(color: Color(0xFF444466), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _nutLegend(String label, Color color, {bool dashed = false}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : color,
            border: dashed ? Border.all(color: color, width: 1) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Color(0xFF888899), fontSize: 11)),
      ],
    );
  }

  Widget _buildNutRow(DailyNutritionSummary s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          Text(s.date,
              style: const TextStyle(color: Color(0xFF888899), fontSize: 12)),
          const Spacer(),
          _nutBadge('${s.calories.round()}', 'kcal', const Color(0xFFFFD700)),
          const SizedBox(width: 10),
          _nutBadge('${s.proteinG.round()}g', 'P', const Color(0xFF3498DB)),
          const SizedBox(width: 10),
          _nutBadge('${s.carbsG.round()}g', 'C', const Color(0xFF2ECC71)),
          const SizedBox(width: 10),
          _nutBadge('${s.fatG.round()}g', 'F', const Color(0xFFE67E22)),
        ],
      ),
    );
  }

  Widget _nutBadge(String value, String label, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Color(0xFF444466), fontSize: 9)),
      ],
    );
  }
}

// ─── PROGRESS DETAIL ROW ─────────────────────────────────────────────────────

class _ProgressDetailRow extends StatelessWidget {
  final String date;
  final double weight;
  final double? delta;
  final bool isFirst;

  const _ProgressDetailRow({
    required this.date,
    required this.weight,
    required this.delta,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (delta == null) {
      statusColor = const Color(0xFF888899);
      statusIcon = Icons.fiber_new;
      statusText = 'First session';
    } else if (delta! > 0) {
      statusColor = const Color(0xFF2ECC71);
      statusIcon = Icons.arrow_upward;
      statusText =
          '+${_fmtW(delta!)} kg (+${(delta! / (weight - delta!) * 100).toStringAsFixed(1)}%)';
    } else if (delta! < 0) {
      statusColor = const Color(0xFFE74C3C);
      statusIcon = Icons.arrow_downward;
      statusText =
          '${_fmtW(delta!)} kg (${(delta! / (weight - delta!) * 100).toStringAsFixed(1)}%)';
    } else {
      statusColor = const Color(0xFFF39C12);
      statusIcon = Icons.remove;
      statusText = 'No change';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDate(date),
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 11),
                ),
                Text(
                  '${_fmtW(weight)} kg',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtW(double w) =>
      w == w.truncate() ? w.toInt().toString() : w.toStringAsFixed(1);

  String _fmtDate(String date) {
    try {
      return DateFormat('MMM d, yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

}

// ─── HELPER WIDGETS ──────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 12)),
            ],
          ),
        ),
      );
}
