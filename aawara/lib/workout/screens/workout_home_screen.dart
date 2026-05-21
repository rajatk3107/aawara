import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/workout_database.dart';
import '../models/workout_log.dart';
import 'workout_logging_screen.dart';
import 'exercise_library_screen.dart';
import 'progress_screen.dart';
import 'workout_history_screen.dart';
import 'quick_start_screen.dart';
import 'achievements_screen.dart';
import 'monthly_summary_screen.dart';
import '../../notes/notes_list_screen.dart';
import '../../settings_screen.dart';
import '../../nutrition/models/nutrition_models.dart';
import '../../nutrition/screens/nutrition_screen.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _db = WorkoutDatabase.instance;

  DateTime _selectedDate = DateTime.now();
  List<WorkoutLog> _dayLogs = [];

  WorkoutLog? get _activeLog {
    try { return _dayLogs.firstWhere((l) => !l.completed); }
    catch (_) { return null; }
  }

  // Stats
  int _streak = 0;
  int _weeklyCount = 0;
  int _monthlyCount = 0;
  double? _latestWeight;
  String? _userGoal;

  // Week strip
  Set<String> _weekCompletedDates = {};

  // Wellness check-in
  bool _showWellnessCard = false;
  double _wellnessSleep = 7.5;
  int _wellnessEnergy = 3;
  int _wellnessSoreness = 2;
  bool _loggingWellness = false;

  // Nutrition summary
  double _todayProteinG = 0;
  double _todayCalories = 0;
  double _proteinGoalG = 150;
  double _calorieGoalKcal = 2000;

  // Water
  WaterLog? _todayWater;

  bool _loading = true;

  String get _dateStr {
    final d = _selectedDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get _isFuture {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final selMidnight = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);
    return selMidnight.isAfter(todayMidnight);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userGoal = prefs.getString('user_goal');

      final now = DateTime.now();
      final weekMonday = now.subtract(Duration(days: now.weekday - 1));
      final weekSunday = weekMonday.add(const Duration(days: 6));
      final weekFrom = _fmt(weekMonday);
      final weekTo = _fmt(weekSunday);
      final todayStr = _fmt(now);

      final results = await Future.wait([
        _db.getWorkoutLogsForDate(_dateStr),
        _db.getWorkoutStreak(),
        _db.getWeeklyWorkoutCount(),
        _db.getMonthlyWorkoutCount(),
        _db.getLatestBodyWeight(),
        _db.getCompletedWorkoutDatesInRange(weekFrom, weekTo),
        _db.getWellnessForDate(todayStr),
        _db.getTodayTotals(todayStr),
        _db.getNutritionGoals(),
        _db.getWaterLog(todayStr),
      ]);

      final logs = results[0] as List<WorkoutLog>;
      final streak = results[1] as int;
      final weekly = results[2] as int;
      final monthly = results[3] as int;
      final weight = results[4] as double?;
      final completedDates = results[5] as Set<String>;
      final todayWellness = results[6] as Map<String, dynamic>?;
      final nutrition = results[7] as NutritionTotals;
      final nutGoals = (results[8] as NutritionGoals?) ?? NutritionGoals.defaults;
      final waterLog = results[9] as WaterLog;

      if (mounted) {
        setState(() {
          _dayLogs = logs;
          _streak = streak;
          _weeklyCount = weekly;
          _monthlyCount = monthly;
          _latestWeight = weight;
          _weekCompletedDates = completedDates;
          _userGoal = userGoal;
          _showWellnessCard = todayWellness == null;
          _todayProteinG = nutrition.proteinG;
          _todayCalories = nutrition.calories;
          _proteinGoalG = nutGoals.proteinG;
          _calorieGoalKcal = nutGoals.calories;
          _todayWater = waterLog;
          _loading = false;
        });

        // Monthly summary — show once on first open of a new month
        final currentMonth =
            '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final lastShown = prefs.getString('last_summary_shown_month') ?? '';
        if (lastShown != currentMonth) {
          await prefs.setString('last_summary_shown_month', currentMonth);
          final prevMonth = now.month == 1 ? 12 : now.month - 1;
          final prevYear = now.month == 1 ? now.year - 1 : now.year;
          final summary = await _db.getMonthlySummary(prevYear, prevMonth);
          if ((summary['total_sessions'] as int) > 0 && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MonthlySummaryScreen(
                        year: prevYear, month: prevMonth),
                  ),
                );
              }
            });
          }
        }

        // Achievement check
        final newAchievements =
            await _db.checkAndUnlockAchievements();
        for (final id in newAchievements) {
          if (mounted) await showAchievementCelebration(context, id);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadForDate() async {
    try {
      final logs = await _db.getWorkoutLogsForDate(_dateStr);
      if (mounted) setState(() => _dayLogs = logs);
    } catch (_) {}
  }

  Future<void> _startWorkoutFlow() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _StartWorkoutSheet(
        onQuickStart: () async {
          Navigator.pop(context);
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => QuickStartScreen(targetDate: _dateStr)),
          );
          _load();
        },
        onCustom: () async {
          Navigator.pop(context);
          await _startCustomWorkout();
        },
      ),
    );
  }

  Future<void> _startCustomWorkout() async {
    const uuid = Uuid();
    final log = WorkoutLog(
      id: uuid.v4(),
      date: _dateStr,
      workoutName: 'Custom Workout',
    );
    final created = await _db.createWorkoutLog(log);
    final fullLog = await _db.getWorkoutLogById(created.id);
    if (fullLog != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WorkoutLoggingScreen(workoutLog: fullLog)),
      );
      _load();
    }
  }

  Future<void> _openLog([WorkoutLog? specificLog]) async {
    final log = specificLog ?? (_dayLogs.isEmpty ? null : _dayLogs.last);
    if (log == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutLoggingScreen(workoutLog: log)),
    );
    _load();
  }

  Future<void> _showWeightDialog() async {
    final controller = TextEditingController(
      text: _latestWeight != null ? _latestWeight!.toStringAsFixed(1) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Weight',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '0.0',
                  hintStyle: TextStyle(color: Color(0xFF555577)),
                ),
              ),
            ),
            const Text(' kg',
                style: TextStyle(color: Colors.white54, fontSize: 18)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child:
                const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result > 0) {
      await _db.logBodyWeight(_dateStr, result);
      setState(() => _latestWeight = result);
    }
  }

  void _showDayOptions() {
    final logs = List<WorkoutLog>.from(_dayLogs);
    final hasLog = logs.isNotEmpty;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat('EEEE, MMM d').format(_selectedDate),
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Day Options',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (!hasLog)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  'No workout logged on this day.',
                  style: const TextStyle(color: Color(0xFF555577), fontSize: 14),
                ),
              )
            else ...[
              // Individual session delete tiles
              ...logs.asMap().entries.map((e) {
                final idx = e.key;
                final log = e.value;
                final sessionLabel = logs.length > 1
                    ? 'Session ${idx + 1} · ${log.workoutName}'
                    : log.workoutName;
                return _OptionTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete $sessionLabel',
                  subtitle: log.completed
                      ? '${log.totalSets} sets · ${log.totalVolume.toStringAsFixed(0)} kg'
                      : 'In progress',
                  color: const Color(0xFFE74C3C),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirm = await _confirmDialog(
                      'Delete Session?',
                      'This will permanently delete "$sessionLabel".',
                      confirmLabel: 'Delete',
                      confirmColor: const Color(0xFFE74C3C),
                    );
                    if (confirm == true) {
                      await _db.deleteWorkoutLog(log.id);
                      _load();
                    }
                  },
                );
              }),
              // Clear All — only shown when multiple sessions exist
              if (logs.length > 1) ...[
                const Divider(color: Color(0xFF1E1E35), height: 24),
                _OptionTile(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Clear All Sessions',
                  subtitle: 'Remove all ${logs.length} sessions for this day',
                  color: const Color(0xFFE74C3C),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirm = await _confirmDialog(
                      'Clear All Sessions?',
                      'This will permanently delete all ${logs.length} workout sessions for this day.',
                      confirmLabel: 'Clear All',
                      confirmColor: const Color(0xFFE74C3C),
                    );
                    if (confirm == true) {
                      for (final l in logs) {
                        await _db.deleteWorkoutLog(l.id);
                      }
                      _load();
                    }
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDialog(String title, String body,
      {required String confirmLabel, required Color confirmColor}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(body,
            style: const TextStyle(color: Colors.white54, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(confirmLabel,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : SafeArea(
              child: RefreshIndicator(
                color: const Color(0xFFFFD700),
                backgroundColor: const Color(0xFF1A1A2E),
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                            child: _buildHeader())),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: _buildWeekStrip())),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: _buildWorkoutCard())),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            child: _buildStatsStrip())),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: _buildNutritionPill())),
                    if (_showWellnessCard)
                      SliverToBoxAdapter(
                          child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: _buildWellnessCard())),
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                            child: _buildQuickAccess())),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    switch (_userGoal) {
      case 'muscle_gain':
        greeting = 'Ready to build?';
      case 'strength':
        greeting = 'Time to get strong.';
      case 'weight_loss':
        greeting = "Let's burn it.";
      case 'general_fitness':
        greeting = 'Stay active!';
      default:
        if (hour < 12) {
          greeting = 'Good morning!';
        } else if (hour < 17) {
          greeting = 'Ready to train?';
        } else {
          greeting = 'Evening session?';
        }
    }
    final dayName = DateFormat('EEEE').format(now);
    final dateLabel = DateFormat('MMM d').format(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dayName · $dateLabel',
                  style: const TextStyle(
                      color: Color(0xFF555577),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  greeting,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3),
                ),
              ],
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen())),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1E1E35)),
                  ),
                  child: const Icon(Icons.settings_rounded,
                      color: Colors.white54, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotesListScreen())),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1E1E35)),
                  ),
                  child: const Icon(Icons.edit_note_rounded,
                      color: Colors.white54, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AchievementsScreen())),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      'A',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Week Plan Strip ─────────────────────────────────────────────────────────

  Widget _buildWeekStrip() {
    final now = DateTime.now();
    final weekMonday = now.subtract(Duration(days: now.weekday - 1));
    final dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'THIS WEEK',
                style: const TextStyle(
                    color: Color(0xFF555577),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
              Text(
                '$_weeklyCount / 7',
                style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final dayDate = weekMonday.add(Duration(days: i));
              final dateStr = _fmt(dayDate);
              final isDone = _weekCompletedDates.contains(dateStr);
              final isToday = (i + 1) == now.weekday;
              final isSelected = _selectedDate.year == dayDate.year &&
                  _selectedDate.month == dayDate.month &&
                  _selectedDate.day == dayDate.day;
              final isFuture = dayDate.isAfter(DateTime(now.year, now.month, now.day));

              final dotColor = isDone
                  ? const Color(0xFF2ECC71)
                  : isToday
                      ? const Color(0xFFFFD700)
                      : isFuture
                          ? const Color(0xFF2A2A45)
                          : const Color(0xFF3A3A55);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedDate = dayDate);
                    _loadForDate();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          dayLetters[i],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSelected || isToday
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF555577),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${dayDate.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDone
                                ? const Color(0xFF2ECC71)
                                : isSelected || isToday
                                    ? Colors.white
                                    : isFuture
                                        ? const Color(0xFF333355)
                                        : const Color(0xFF666688),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── Workout Card ─────────────────────────────────────────────────────────────

  Widget _buildWorkoutCard() {
    final activeLog = _activeLog;
    final isInProgress = activeLog != null;
    final hasAnySessions = _dayLogs.isNotEmpty;
    final allCompleted = hasAnySessions && !isInProgress;
    final sessionCount = _dayLogs.length;
    final lastLog = _dayLogs.isEmpty ? null : _dayLogs.last;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isInProgress
              ? const Color(0xFFF39C12).withValues(alpha: 0.3)
              : allCompleted
                  ? const Color(0xFF2ECC71).withValues(alpha: 0.2)
                  : const Color(0xFF1E1E35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // State badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isInProgress
                              ? const Color(0xFFF39C12)
                              : allCompleted
                                  ? const Color(0xFF2ECC71)
                                  : const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          isInProgress
                              ? sessionCount > 1
                                  ? 'SESSION $sessionCount · IN PROGRESS'
                                  : 'IN PROGRESS'
                              : allCompleted
                                  ? sessionCount > 1
                                      ? 'DONE · $sessionCount SESSIONS'
                                      : 'DONE'
                                  : _isFuture
                                      ? DateFormat('EEE, MMM d')
                                          .format(_selectedDate)
                                          .toUpperCase()
                                      : 'TODAY',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isInProgress
                            ? activeLog.workoutName
                            : allCompleted
                                ? lastLog!.workoutName
                                : 'Ready to train?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 4),
                      if (allCompleted && sessionCount == 1)
                        Text(
                          '${lastLog!.exercises.length} exercises  ·  '
                          '${lastLog.totalSets} sets  ·  '
                          '${lastLog.totalVolume.toStringAsFixed(0)} kg',
                          style: const TextStyle(
                              color: Color(0xFF888899), fontSize: 12),
                        ),
                      if (allCompleted && sessionCount > 1)
                        Text(
                          '${_dayLogs.fold(0, (s, l) => s + l.totalSets)} sets  ·  '
                          '${_dayLogs.fold(0.0, (s, l) => s + l.totalVolume).toStringAsFixed(0)} kg total',
                          style: const TextStyle(
                              color: Color(0xFF888899), fontSize: 12),
                        ),
                      if (!hasAnySessions)
                        const Text(
                          'Quick Start or build your own from scratch',
                          style: TextStyle(
                              color: Color(0xFF555577), fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 108,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    if (isInProgress)
                      _PillButton(
                        label: 'Resume',
                        icon: Icons.play_arrow_rounded,
                        color: const Color(0xFFF39C12),
                        onTap: () => _openLog(activeLog),
                      )
                    else if (!_isFuture)
                      _PillButton(
                        label: allCompleted ? 'Session' : 'Start',
                        icon: allCompleted
                            ? Icons.add_rounded
                            : Icons.play_arrow_rounded,
                        color: allCompleted
                            ? const Color(0xFF3498DB)
                            : const Color(0xFFFFD700),
                        onTap: _startWorkoutFlow,
                      ),
                    if (allCompleted) ...[
                      const SizedBox(height: 6),
                      _PillButton(
                        label: 'View',
                        icon: Icons.visibility_outlined,
                        color: const Color(0xFF2ECC71),
                        onTap: () => _openLog(lastLog),
                      ),
                    ],
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _showDayOptions,
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2A2A45)),
                        ),
                        child: const Icon(Icons.more_horiz_rounded,
                            color: Colors.white38, size: 18),
                      ),
                    ),
                  ],
                  ),
                ),
              ],
            ),
          ),

          // Session list (shown when multiple sessions exist)
          if (sessionCount > 1) _buildSessionList(),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          const Divider(color: Color(0xFF1E1E35), height: 1),
          const SizedBox(height: 8),
          ..._dayLogs.asMap().entries.map((e) {
            final idx = e.key;
            final log = e.value;
            final isActive = !log.completed;
            final dur = log.durationSeconds;
            final durStr = dur != null ? '${dur ~/ 60}m' : '';
            return GestureDetector(
              onTap: () => _openLog(log),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFF39C12).withValues(alpha: 0.07)
                      : const Color(0xFF0D0D1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFF39C12).withValues(alpha: 0.3)
                        : const Color(0xFF1E1E35),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Session ${idx + 1}',
                      style: const TextStyle(
                          color: Color(0xFF555577),
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.workoutName,
                        style: const TextStyle(
                            color: Color(0xFFCCCCDD),
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (durStr.isNotEmpty) ...[
                      Text(durStr,
                          style: const TextStyle(
                              color: Color(0xFF555577), fontSize: 11)),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      isActive
                          ? Icons.radio_button_checked
                          : Icons.check_circle_rounded,
                      color: isActive
                          ? const Color(0xFFF39C12)
                          : const Color(0xFF2ECC71),
                      size: 15,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Stats Strip ─────────────────────────────────────────────────────────────

  Widget _buildStatsStrip() {
    final isInProgress = _activeLog != null;
    final isCompleted = _dayLogs.isNotEmpty && !isInProgress;

    String todayStatus;
    Color todayColor;
    IconData todayIcon;
    if (isCompleted) {
      todayStatus = 'Done';
      todayColor = const Color(0xFF2ECC71);
      todayIcon = Icons.check_circle_rounded;
    } else if (isInProgress) {
      todayStatus = 'Active';
      todayColor = const Color(0xFFF39C12);
      todayIcon = Icons.radio_button_checked;
    } else {
      todayStatus = 'Pending';
      todayColor = const Color(0xFF555577);
      todayIcon = Icons.radio_button_unchecked;
    }

    final stats = [
      _StatData(Icons.local_fire_department_rounded, '${_streak}d',
          'Streak', const Color(0xFFFF6B35)),
      _StatData(Icons.calendar_today_rounded, '$_weeklyCount/7',
          'This Week', const Color(0xFF9B59B6)),
      _StatData(Icons.monitor_weight_outlined,
          _latestWeight != null
              ? '${_latestWeight!.toStringAsFixed(1)}'
              : '—',
          'kg', const Color(0xFF3498DB),
          onTap: _showWeightDialog),
      _StatData(Icons.fitness_center_rounded, '$_monthlyCount',
          'Month', const Color(0xFFF472B6)),
      _StatData(todayIcon, todayStatus, 'Today', todayColor),
      _StatData(
        Icons.water_drop_rounded,
        _todayWater != null
            ? '${_todayWater!.glassesDrunk}/${_todayWater!.targetGlasses}'
            : '—',
        'Water',
        const Color(0xFF4FC3F7),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NutritionScreen())),
      ),
    ];

    return Row(
      children: stats.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        return Expanded(
          child: GestureDetector(
            onTap: s.onTap,
            child: Container(
              margin: EdgeInsets.only(right: i < 5 ? 7 : 0),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E35)),
              ),
              child: Column(
                children: [
                  Icon(s.icon, color: s.color, size: 14),
                  const SizedBox(height: 4),
                  Text(
                    s.value,
                    style: TextStyle(
                        color: s.color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.label,
                    style: const TextStyle(
                        color: Color(0xFF444466),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNutritionPill() {
    final protPct = (_proteinGoalG > 0
            ? (_todayProteinG / _proteinGoalG).clamp(0.0, 1.0)
            : 0.0);
    final calPct = (_calorieGoalKcal > 0
            ? (_todayCalories / _calorieGoalKcal).clamp(0.0, 1.0)
            : 0.0);
    final protOver = _todayProteinG >= _proteinGoalG;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded,
              color: Color(0xFF3498DB), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Protein  ${_todayProteinG.round()}g / ${_proteinGoalG.round()}g',
                      style: const TextStyle(
                          color: Color(0xFFCCCCDD),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${_todayCalories.round()} kcal',
                      style: const TextStyle(
                          color: Color(0xFF555577), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: protPct,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF0D0D1A),
                          valueColor: AlwaysStoppedAnimation(
                            protOver
                                ? const Color(0xFF2ECC71)
                                : const Color(0xFF3498DB),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: calPct,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF0D0D1A),
                          valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFFFD700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Wellness Check-in Card ──────────────────────────────────────────────────

  Future<void> _logWellness() async {
    setState(() => _loggingWellness = true);
    final today = _fmt(DateTime.now());
    await _db.logWellness(
      date: today,
      sleepHours: _wellnessSleep,
      energy: _wellnessEnergy,
      soreness: _wellnessSoreness,
    );
    if (mounted) setState(() { _showWellnessCard = false; _loggingWellness = false; });
  }

  Widget _buildWellnessCard() {
    const energyEmojis = ['😴', '😕', '😐', '🙂', '⚡'];
    const sorenessColors = [
      Color(0xFF2ECC71),
      Color(0xFF8CC152),
      Color(0xFFF1C40F),
      Color(0xFFE67E22),
      Color(0xFFE74C3C),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          // Sleep stepper
          _WellnessLabel('😴'),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: () => setState(() {
              if (_wellnessSleep > 5.0) _wellnessSleep -= 0.5;
            }),
            child: const Icon(Icons.remove_rounded,
                color: Color(0xFF555577), size: 16),
          ),
          const SizedBox(width: 4),
          Text(
            _wellnessSleep.toStringAsFixed(1),
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => setState(() {
              if (_wellnessSleep < 10.0) _wellnessSleep += 0.5;
            }),
            child: const Icon(Icons.add_rounded,
                color: Color(0xFF555577), size: 16),
          ),
          const SizedBox(width: 10),
          // Energy
          _WellnessLabel('⚡'),
          const SizedBox(width: 4),
          ...List.generate(5, (i) {
            final sel = _wellnessEnergy == i + 1;
            return GestureDetector(
              onTap: () => setState(() => _wellnessEnergy = i + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  energyEmojis[i],
                  style: TextStyle(
                      fontSize: sel ? 17 : 13,
                      color: sel ? null : const Color(0xFF555577)),
                ),
              ),
            );
          }),
          const SizedBox(width: 10),
          // Soreness
          _WellnessLabel('🦴'),
          const SizedBox(width: 4),
          ...List.generate(5, (i) {
            final sel = _wellnessSoreness == i + 1;
            return GestureDetector(
              onTap: () => setState(() => _wellnessSoreness = i + 1),
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: sel ? 10 : 7,
                  height: sel ? 10 : 7,
                  decoration: BoxDecoration(
                    color: sel
                        ? sorenessColors[i]
                        : sorenessColors[i].withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Log button
          GestureDetector(
            onTap: _loggingWellness ? null : _logWellness,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _loggingWellness
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Log',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick Access ─────────────────────────────────────────────────────────────

  Widget _buildQuickAccess() {
    final items = [
      _NavItem(Icons.bar_chart_rounded, 'Progress', 'Charts & PRs',
          const Color(0xFF2ECC71), () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ProgressScreen()));
      }),
      _NavItem(Icons.sports_gymnastics_rounded, 'Exercises', 'Library',
          const Color(0xFF3498DB), () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()));
      }),
      _NavItem(Icons.bolt_rounded, 'Quick Start', 'Presets & templates',
          const Color(0xFF9B59B6), () async {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => QuickStartScreen(targetDate: _dateStr)));
        _load();
      }),
      _NavItem(Icons.history_rounded, 'History', 'Past workouts',
          const Color(0xFFE67E22), () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()));
      }),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK ACCESS',
          style: TextStyle(
              color: Color(0xFF444466),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.0,
          children: items.map((item) => _NavCard(item: item)).toList(),
        ),
      ],
    );
  }
}

// ─── Start Workout Picker Sheet ───────────────────────────────────────────────

class _StartWorkoutSheet extends StatelessWidget {
  final VoidCallback onQuickStart;
  final VoidCallback onCustom;

  const _StartWorkoutSheet({
    required this.onQuickStart,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Start Workout',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose how you want to train today',
            style: TextStyle(color: Color(0xFF555577), fontSize: 13),
          ),
          const SizedBox(height: 20),
          // Quick Start option
          _SheetOption(
            icon: Icons.bolt_rounded,
            color: const Color(0xFFFFD700),
            title: 'Quick Start',
            subtitle: 'Pick from PPL presets or muscle-group templates.\nEdit exercises before you begin.',
            onTap: onQuickStart,
          ),
          const SizedBox(height: 12),
          // Custom option
          _SheetOption(
            icon: Icons.tune_rounded,
            color: const Color(0xFF3498DB),
            title: 'Custom Workout',
            subtitle: 'Start a blank session and add exercises as you go.',
            onTap: onCustom,
          ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF12121F),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF555577),
                            fontSize: 12,
                            height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _WellnessLabel extends StatelessWidget {
  final String emoji;
  const _WellnessLabel(this.emoji);
  @override
  Widget build(BuildContext context) =>
      Text(emoji, style: const TextStyle(fontSize: 13));
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _StatData(this.icon, this.value, this.label, this.color, {this.onTap});
}

class _NavItem {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  _NavItem(this.icon, this.label, this.sub, this.color, this.onTap);
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

class _NavCard extends StatelessWidget {
  final _NavItem item;
  const _NavCard({required this.item});

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        item.sub,
                        style: const TextStyle(
                            color: Color(0xFF555577),
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.4), size: 18),
              ],
            ),
          ),
        ),
      );
}
