import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_plan_day.dart';
import '../models/workout_log.dart';
import 'workout_logging_screen.dart';
import 'workout_plan_screen.dart';
import 'exercise_library_screen.dart';
import 'progress_screen.dart';
import 'workout_history_screen.dart';
import 'quick_start_screen.dart';
import '../../notes/notes_list_screen.dart';
import 'package:uuid/uuid.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _db = WorkoutDatabase.instance;

  DateTime _selectedDate = DateTime.now();
  WorkoutPlanDay? _dayPlan;
  WorkoutLog? _dayLog;
  List<Exercise> _dayExercises = [];
  int _streak = 0;
  int _weeklyCount = 0;
  double? _latestWeight;
  bool _loading = true;

  String get _dateStr {
    final d = _selectedDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  bool get _isFuture {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final selMidnight = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
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
      final planDay = await _db.getPlanDayForWeekday(_selectedDate.weekday);
      final log = await _db.getWorkoutLogForDate(_dateStr);
      final streak = await _db.getWorkoutStreak();
      final weekly = await _db.getWeeklyWorkoutCount();
      final weight = await _db.getLatestBodyWeight();

      List<Exercise> exercises = [];
      if (planDay != null && !planDay.isRestDay) {
        final override = await _db.getDayOverride(_dateStr);
        final ids = override ?? planDay.exerciseIds;
        for (final id in ids) {
          final ex = await _db.getExerciseById(id);
          if (ex != null) exercises.add(ex);
        }
      }

      if (mounted) {
        setState(() {
          _dayPlan = planDay;
          _dayLog = log;
          _dayExercises = exercises;
          _streak = streak;
          _weeklyCount = weekly;
          _latestWeight = weight;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevDay() {
    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
    _load();
  }

  void _nextDay() {
    if (_isToday) return;
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  /// Opens pre-workout setup: plan exercises pre-loaded, user can edit before starting.
  Future<void> _logWorkout() async {
    if (_dayExercises.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuickStartScreen(
            targetDate: _dateStr,
            preloadedName: _dayPlan?.workoutName ?? 'Workout',
            preloadedExercises: _dayExercises,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QuickStartScreen(targetDate: _dateStr)),
      );
    }
    _load();
  }

  Future<void> _openLog() async {
    if (_dayLog == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutLoggingScreen(workoutLog: _dayLog!)),
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
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(
                    color: Color(0xFFFFD700), fontSize: 28, fontWeight: FontWeight.bold),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _toggleRestDay() async {
    if (_dayPlan == null) return;
    final updated = _dayPlan!.copyWith(isRestDay: !_dayPlan!.isRestDay);
    await _db.savePlanDay(updated);
    _load();
  }

  /// Shows a bottom sheet with options to edit or clear the day's workout.
  void _showDayOptions() {
    final hasLog = _dayLog != null;
    final isRest = _dayPlan?.isRestDay ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
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
                  color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            const Text(
              'Day Options',
              style: TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Clear logged workout
            if (hasLog)
              _OptionTile(
                icon: Icons.delete_sweep_outlined,
                label: 'Clear Workout Log',
                subtitle: 'Remove all logged sets and exercises for this day',
                color: const Color(0xFFE74C3C),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await _confirmDialog(
                    'Clear Workout Log?',
                    'This will permanently delete the logged workout for this day.',
                    confirmLabel: 'Clear',
                    confirmColor: const Color(0xFFE74C3C),
                  );
                  if (confirm == true) {
                    await _db.deleteWorkoutLog(_dayLog!.id);
                    _load();
                  }
                },
              ),

            // Mark as rest / un-rest
            if (_dayPlan != null)
              _OptionTile(
                icon: isRest
                    ? Icons.fitness_center_rounded
                    : Icons.self_improvement_rounded,
                label: isRest ? 'Change to Workout Day' : 'Mark as Rest Day',
                subtitle: isRest
                    ? 'Switch this day back to a workout day'
                    : 'Mark this day as rest — clears plan and log',
                color: isRest
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF3498DB),
                onTap: () async {
                  Navigator.pop(context);
                  if (!isRest && hasLog) {
                    // Confirm clearing log when switching to rest
                    final confirm = await _confirmDialog(
                      'Mark as Rest Day?',
                      'This will also delete the workout log for this day.',
                      confirmLabel: 'Mark Rest',
                      confirmColor: const Color(0xFF3498DB),
                    );
                    if (confirm != true) return;
                    await _db.deleteWorkoutLog(_dayLog!.id);
                  }
                  _toggleRestDay();
                },
              ),

            // Edit weekly plan
            _OptionTile(
              icon: Icons.edit_calendar_outlined,
              label: 'Edit Weekly Plan',
              subtitle: 'Change exercises or settings for this weekday',
              color: const Color(0xFF9B59B6),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()));
                _load();
              },
            ),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(body,
            style: const TextStyle(color: Colors.white54, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : SafeArea(
              child: RefreshIndicator(
                color: const Color(0xFFFFD700),
                backgroundColor: const Color(0xFF1A1A2E),
                onRefresh: _load,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildDateNav()),
                    SliverToBoxAdapter(child: const SizedBox(height: 16)),
                    SliverToBoxAdapter(child: _buildWorkoutCard()),
                    SliverToBoxAdapter(child: const SizedBox(height: 16)),
                    SliverToBoxAdapter(child: _buildStatsRow()),
                    SliverToBoxAdapter(child: const SizedBox(height: 24)),
                    SliverToBoxAdapter(child: _buildQuickAccess()),
                    SliverToBoxAdapter(child: const SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Image.asset('assets/app-icon.png', width: 32, height: 32),
          const SizedBox(width: 10),
          const Text(
            'Aawara',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotesListScreen())),
            icon: const Icon(Icons.note_alt_outlined, color: Colors.white38, size: 22),
          ),
        ],
      ),
    );
  }

  // ─── Date Navigator ───────────────────────────────────────────────────────

  Widget _buildDateNav() {
    final label = _isToday
        ? 'Today'
        : DateFormat('EEEE').format(_selectedDate);
    final sub = DateFormat('MMM d, yyyy').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _CircleBtn(icon: Icons.chevron_left, onTap: _prevDay),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: _isToday
                          ? const Color(0xFFFFD700)
                          : _isFuture
                              ? const Color(0xFF3498DB)
                              : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  Text(sub,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ),
          _CircleBtn(
            icon: Icons.chevron_right,
            onTap: _isToday ? null : _nextDay,
            disabled: _isToday,
          ),
        ],
      ),
    );
  }

  // ─── Main Workout Card ────────────────────────────────────────────────────

  Widget _buildWorkoutCard() {
    final isRest = _dayPlan?.isRestDay ?? false;
    final noPlan = _dayPlan == null;
    final isCompleted = _dayLog?.completed == true;
    final isInProgress = _dayLog != null && !isCompleted;

    Color accentColor;
    IconData statusIcon;
    String title;
    String subtitle;

    if (isCompleted) {
      accentColor = const Color(0xFF2ECC71);
      statusIcon = Icons.check_circle_rounded;
      title = _dayLog!.workoutName;
      subtitle = '${_dayLog!.totalSets} sets · ${_dayLog!.totalVolume.toStringAsFixed(0)} kg volume';
    } else if (isInProgress) {
      accentColor = const Color(0xFFF39C12);
      statusIcon = Icons.play_circle_fill_rounded;
      title = _dayLog!.workoutName;
      subtitle = 'In progress · ${_dayLog!.totalSets} sets logged';
    } else if (isRest) {
      accentColor = const Color(0xFF3498DB);
      statusIcon = Icons.self_improvement_rounded;
      title = 'Rest Day';
      subtitle = 'Recovery is part of the progress';
    } else if (noPlan) {
      accentColor = const Color(0xFF888899);
      statusIcon = Icons.add_circle_outline_rounded;
      title = 'No Workout Planned';
      subtitle = 'Use Quick Start or set up your weekly plan';
    } else {
      accentColor = const Color(0xFFFFD700);
      statusIcon = Icons.fitness_center_rounded;
      title = _dayPlan!.workoutName;
      subtitle = '${_dayExercises.length} exercises planned';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: accentColor.withValues(alpha: isCompleted ? 0.35 : 0.15),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(statusIcon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (_isFuture)
                    _Badge(label: 'Upcoming', color: const Color(0xFF3498DB)),
                  IconButton(
                    onPressed: _showDayOptions,
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Colors.white24, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // Exercise preview (for planned workout days)
            if (!isRest && !noPlan && !isCompleted && !isInProgress && _dayExercises.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Divider(color: Color(0xFF1E1E35), height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                child: Column(
                  children: _dayExercises.take(4).map((ex) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(ex.name,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const Spacer(),
                        Text(ex.muscleGroup,
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 11)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
              if (_dayExercises.length > 4)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Text(
                    '+${_dayExercises.length - 4} more',
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                ),
            ],

            // Completed summary
            if (isCompleted) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Divider(color: Color(0xFF1E1E35), height: 1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                        label: 'Exercises',
                        value: '${_dayLog!.exercises.length}',
                        color: const Color(0xFF2ECC71)),
                    _MiniStat(
                        label: 'Sets',
                        value: '${_dayLog!.totalSets}',
                        color: const Color(0xFF2ECC71)),
                    _MiniStat(
                        label: 'Volume',
                        value: '${_dayLog!.totalVolume.toStringAsFixed(0)} kg',
                        color: const Color(0xFF2ECC71)),
                  ],
                ),
              ),
            ],

            // CTA Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: _buildCardCTA(isRest, noPlan, isCompleted, isInProgress, accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardCTA(
      bool isRest, bool noPlan, bool isCompleted, bool isInProgress, Color accentColor) {
    if (isRest) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _GoldButton(
                  label: 'Train Anyway',
                  icon: Icons.fitness_center,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (_) => QuickStartScreen(targetDate: _dateStr),
                    ));
                    _load();
                  },
                  outlined: true,
                  color: const Color(0xFF3498DB),
                ),
              ),
              const SizedBox(width: 10),
              _SmallBtn(
                label: 'Edit Day',
                icon: Icons.swap_horiz,
                onTap: _toggleRestDay,
              ),
            ],
          ),
        ],
      );
    }

    if (isCompleted) {
      return _GoldButton(
        label: 'View Workout',
        icon: Icons.visibility_outlined,
        onTap: _openLog,
        color: const Color(0xFF2ECC71),
      );
    }

    if (isInProgress) {
      return _GoldButton(
        label: 'Continue Workout',
        icon: Icons.play_arrow_rounded,
        onTap: _openLog,
      );
    }

    if (noPlan) {
      return Row(
        children: [
          Expanded(
            child: _GoldButton(
              label: 'Quick Start',
              icon: Icons.bolt_rounded,
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => QuickStartScreen(targetDate: _dateStr),
                ));
                _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          _SmallBtn(
            label: 'Set Plan',
            icon: Icons.calendar_month,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()));
              _load();
            },
          ),
        ],
      );
    }

    // Has plan, not logged
    return Row(
      children: [
        Expanded(
          child: _GoldButton(
            label: _isFuture ? 'Plan Workout' : 'Log Workout',
            icon: Icons.fitness_center_rounded,
            onTap: _logWorkout,
          ),
        ),
        const SizedBox(width: 10),
        _SmallBtn(
          label: 'Quick',
          icon: Icons.bolt_rounded,
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => QuickStartScreen(targetDate: _dateStr),
            ));
            _load();
          },
        ),
      ],
    );
  }

  // ─── Stats Row ────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final isRest = _dayPlan?.isRestDay ?? false;
    final isCompleted = _dayLog?.completed == true;
    final isInProgress = _dayLog != null && !isCompleted;

    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (isRest) {
      statusLabel = 'Rest';
      statusColor = const Color(0xFF3498DB);
      statusIcon = Icons.hotel_rounded;
    } else if (isCompleted) {
      statusLabel = 'Done';
      statusColor = const Color(0xFF2ECC71);
      statusIcon = Icons.check_circle_rounded;
    } else if (isInProgress) {
      statusLabel = 'Active';
      statusColor = const Color(0xFFF39C12);
      statusIcon = Icons.radio_button_checked;
    } else {
      statusLabel = 'Pending';
      statusColor = const Color(0xFF555577);
      statusIcon = Icons.radio_button_unchecked;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.local_fire_department_rounded,
              label: 'Streak',
              value: '${_streak}d',
              color: const Color(0xFFFF6B35),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.calendar_today_rounded,
              label: 'This Week',
              value: '$_weeklyCount / 7',
              color: const Color(0xFF9B59B6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _showWeightDialog,
              child: _StatTile(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight',
                value: _latestWeight != null
                    ? '${_latestWeight!.toStringAsFixed(1)} kg'
                    : 'Log',
                color: const Color(0xFF3498DB),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: statusIcon,
              label: _isToday ? 'Today' : 'Status',
              value: statusLabel,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick Access ─────────────────────────────────────────────────────────

  Widget _buildQuickAccess() {
    final items = [
      _NavItem(Icons.bolt_rounded, 'Quick Start', const Color(0xFFFFD700), () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => QuickStartScreen(targetDate: _dateStr),
        ));
        _load();
      }),
      _NavItem(Icons.calendar_month_rounded, 'Weekly Plan', const Color(0xFF9B59B6), () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WorkoutPlanScreen()));
        _load();
      }),
      _NavItem(Icons.bar_chart_rounded, 'Progress', const Color(0xFF2ECC71), () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProgressScreen()));
      }),
      _NavItem(Icons.history_rounded, 'History', const Color(0xFFE67E22), () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen()));
      }),
      _NavItem(Icons.sports_gymnastics_rounded, 'Exercises', const Color(0xFF3498DB), () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()));
      }),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUICK ACCESS',
            style: TextStyle(
              color: Color(0xFF444466),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.3,
            children: items.map((item) => _NavCard(item: item)).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Data class for nav items ─────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _NavItem(this.icon, this.label, this.color, this.onTap);
}

// ─── HELPER WIDGETS ───────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;
  const _CircleBtn({required this.icon, this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF12121F),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: disabled ? const Color(0xFF222233) : Colors.white60,
            size: 20,
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );
}

class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool outlined;
  final Color color;

  const _GoldButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.outlined = false,
    this.color = const Color(0xFFFFD700),
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: outlined
                ? null
                : LinearGradient(
                    colors: [color, Color.lerp(color, Colors.orange, 0.4)!],
                  ),
            color: outlined ? Colors.transparent : null,
            borderRadius: BorderRadius.circular(14),
            border: outlined ? Border.all(color: color.withValues(alpha: 0.6)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: outlined ? color : Colors.black, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: outlined ? color : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SmallBtn({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2A2A45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white38, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF444466), fontSize: 10)),
          ],
        ),
      );
}

class _NavCard extends StatelessWidget {
  final _NavItem item;
  const _NavCard({required this.item});

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
