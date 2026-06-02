import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/workout_database.dart';
import '../models/exercise.dart';
import '../models/workout_log.dart';
import '../widgets/muscle_group_filter.dart';
import '../../nutrition/models/nutrition_models.dart';
import '../../notes/notes_database.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _Range { today, week, month, year, all, custom }

enum _Format { json, csv }

enum _DataCategory {
  workouts,
  personalRecords,
  nutrition,
  nutritionGoals,
  bodyWeight,
  bodyMeasurements,
  water,
  wellness,
  achievements,
  stepLogs,
  customFoods,
  customExercises,
  mealPresets,
  quickStart,
  dayOverrides,
  notes,
}

typedef _CatInfo = ({String emoji, String label, String desc});

const Map<_DataCategory, _CatInfo> _catInfo = {
  _DataCategory.workouts: (emoji: '🏋️', label: 'Workouts', desc: 'Workout sessions, sets & reps'),
  _DataCategory.personalRecords: (emoji: '🏆', label: 'Personal Records', desc: 'Best lifts & estimated 1RM per exercise'),
  _DataCategory.nutrition: (emoji: '🥗', label: 'Nutrition / Food', desc: 'Daily food diary & per-meal entries'),
  _DataCategory.nutritionGoals: (emoji: '🎯', label: 'Nutrition Goals', desc: 'Daily calorie & macro targets'),
  _DataCategory.bodyWeight: (emoji: '⚖️', label: 'Body Weight', desc: 'Weight tracking history'),
  _DataCategory.bodyMeasurements: (emoji: '📏', label: 'Body Measurements', desc: 'Waist, chest, arms, thighs & all other dimensions'),
  _DataCategory.water: (emoji: '💧', label: 'Water Intake', desc: 'Daily hydration logs'),
  _DataCategory.wellness: (emoji: '🌙', label: 'Wellness', desc: 'Sleep hours, energy & soreness levels'),
  _DataCategory.achievements: (emoji: '🎖️', label: 'Achievements', desc: 'Unlocked badges & milestones'),
  _DataCategory.stepLogs: (emoji: '👟', label: 'Step Logs', desc: 'Daily step count & goals'),
  _DataCategory.customFoods: (emoji: '🥦', label: 'Custom Foods', desc: 'Foods you created manually'),
  _DataCategory.customExercises: (emoji: '💪', label: 'Custom Exercises', desc: 'Exercises you added yourself'),
  _DataCategory.mealPresets: (emoji: '🍽️', label: 'Meal Presets', desc: 'Saved meal templates'),
  _DataCategory.quickStart: (emoji: '⚡', label: 'Quick-Start Templates', desc: 'Saved workout quick-start templates'),
  _DataCategory.dayOverrides: (emoji: '📅', label: 'Schedule Overrides', desc: 'Custom schedule day configurations'),
  _DataCategory.notes: (emoji: '📝', label: 'Notes', desc: 'Personal notes, journals & thoughts'),
};

// Categories available for each export type
const _jsonExportCats = [
  _DataCategory.workouts,
  _DataCategory.personalRecords,
  _DataCategory.nutrition,
  _DataCategory.nutritionGoals,
  _DataCategory.bodyWeight,
  _DataCategory.bodyMeasurements,
  _DataCategory.water,
  _DataCategory.wellness,
  _DataCategory.stepLogs,
];

const _aiExportCats = [
  _DataCategory.workouts,
  _DataCategory.personalRecords,
  _DataCategory.nutrition,
  _DataCategory.nutritionGoals,
  _DataCategory.bodyWeight,
  _DataCategory.bodyMeasurements,
  _DataCategory.water,
  _DataCategory.wellness,
  _DataCategory.achievements,
  _DataCategory.stepLogs,
  _DataCategory.notes,
];

const _backupExportCats = [
  _DataCategory.workouts,
  _DataCategory.personalRecords,
  _DataCategory.nutrition,
  _DataCategory.nutritionGoals,
  _DataCategory.bodyWeight,
  _DataCategory.bodyMeasurements,
  _DataCategory.water,
  _DataCategory.wellness,
  _DataCategory.achievements,
  _DataCategory.stepLogs,
  _DataCategory.customFoods,
  _DataCategory.customExercises,
  _DataCategory.mealPresets,
  _DataCategory.quickStart,
  _DataCategory.dayOverrides,
  _DataCategory.notes,
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _db = WorkoutDatabase.instance;

  _Range _range = _Range.all;
  _Format _format = _Format.csv;

  DateTime _customFrom = DateTime.now().subtract(const Duration(days: 30));
  DateTime _customTo = DateTime.now();

  // Exercise filter
  Exercise? _filterExercise; // null = all exercises

  // Preview counts (updated whenever options change)
  int? _previewWorkouts;
  int? _previewSets;

  bool _exporting = false;
  bool _exportingFullBackup = false;
  bool _exportingAI = false;
  bool _importing = false;
  bool _loadingPreview = false;

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  // ─── Date range helpers ────────────────────────────────────────────────────

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  (String, String) get _fromTo {
    final now = DateTime.now();
    final today = _fmt(now);
    return switch (_range) {
      _Range.today => (today, today),
      _Range.week => (
          _fmt(now.subtract(Duration(days: now.weekday - 1))),
          today
        ),
      _Range.month => (_fmt(DateTime(now.year, now.month, 1)), today),
      _Range.year => (_fmt(DateTime(now.year, 1, 1)), today),
      _Range.all => ('2000-01-01', today),
      _Range.custom => (_fmt(_customFrom), _fmt(_customTo)),
    };
  }

  // ─── Preview ──────────────────────────────────────────────────────────────

  Future<void> _refreshPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewWorkouts = null;
      _previewSets = null;
    });
    final (from, to) = _fromTo;
    final logs = await _db.getWorkoutLogsForExport(
      fromDate: from,
      toDate: to,
      exerciseId: _filterExercise?.id,
    );
    final totalSets = logs.fold(0, (s, l) => s + l.totalSets);
    if (mounted) {
      setState(() {
        _previewWorkouts = logs.length;
        _previewSets = totalSets;
        _loadingPreview = false;
      });
    }
  }

  // ─── Category picker ──────────────────────────────────────────────────────

  Future<Set<_DataCategory>?> _showCategoryPicker({
    required List<_DataCategory> available,
    required Set<_DataCategory> initial,
    required String title,
  }) {
    return showModalBottomSheet<Set<_DataCategory>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPickerSheet(
        available: available,
        initial: initial,
        title: title,
      ),
    );
  }

  // ─── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    final availableCats = _format == _Format.csv
        ? [_DataCategory.workouts]
        : _jsonExportCats;

    final selected = await _showCategoryPicker(
      available: availableCats,
      initial: availableCats.toSet(),
      title: 'What to Export',
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _exporting = true);
    try {
      final (from, to) = _fromTo;
      List<WorkoutLog> logs = [];
      final exerciseMap = <String, Exercise>{};

      if (selected.contains(_DataCategory.workouts)) {
        logs = await _db.getWorkoutLogsForExport(
          fromDate: from,
          toDate: to,
          exerciseId: _filterExercise?.id,
        );
        for (final log in logs) {
          for (final exLog in log.exercises) {
            if (!exerciseMap.containsKey(exLog.exerciseId)) {
              final ex = await _db.getExerciseById(exLog.exerciseId);
              if (ex != null) exerciseMap[exLog.exerciseId] = ex;
            }
          }
        }
      }

      final content = _format == _Format.csv
          ? _buildCsv(logs, exerciseMap)
          : await _buildJson(logs, exerciseMap, selected, from, to);

      final ext = _format == _Format.csv ? 'csv' : 'json';
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'aawara_export_$stamp.$ext';

      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsString(content, encoding: utf8);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path, mimeType: _format == _Format.csv ? 'text/csv' : 'application/json')],
        subject: 'Aawara Workout Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── AI Export ───────────────────────────────────────────────────────────

  Future<void> _exportForAI() async {
    final selected = await _showCategoryPicker(
      available: _aiExportCats,
      initial: _aiExportCats.toSet(),
      title: 'What to Include in AI Export',
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _exportingAI = true);
    try {
      final (from, to) = _fromTo;
      final catNames = selected
          .where((c) => c != _DataCategory.notes)
          .map((c) => c.name)
          .toSet();

      var content = await _db.exportForAI(categories: catNames, fromDate: from, toDate: to);

      if (selected.contains(_DataCategory.notes)) {
        final notes = await NotesDatabase.instance.getNotes();
        if (notes.isNotEmpty) {
          final sb = StringBuffer(content);
          sb.writeln('\n## Personal Notes');
          for (final note in notes) {
            sb.writeln('### ${note.title} (${DateFormat('yyyy-MM-dd').format(note.updatedAt)})');
            // content is Quill Delta JSON — include raw for AI context
            sb.writeln(note.content);
            sb.writeln();
          }
          content = sb.toString();
        }
      }

      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'aawara_ai_export_$stamp.md';
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsString(content, encoding: utf8);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/markdown')],
        subject: 'Aawara — AI Analysis Data',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingAI = false);
    }
  }

  // ─── Full Backup Export ───────────────────────────────────────────────────

  Future<void> _exportFullBackup() async {
    final selected = await _showCategoryPicker(
      available: _backupExportCats,
      initial: _backupExportCats.toSet(),
      title: 'What to Include in Backup',
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() => _exportingFullBackup = true);
    try {
      final catNames = selected
          .where((c) => c != _DataCategory.notes)
          .map((c) => c.name)
          .toSet();

      var content = await _db.exportFullBackup(categories: catNames);

      if (selected.contains(_DataCategory.notes)) {
        final data = jsonDecode(content) as Map<String, dynamic>;
        final notes = await NotesDatabase.instance.getNotes();
        final folders = await NotesDatabase.instance.getFolders();
        final tags = await NotesDatabase.instance.getTags();
        if (notes.isNotEmpty) {
          data['notes'] = notes.map((n) => {
            'id': n.id,
            'title': n.title,
            'content': n.content,
            'folder_id': n.folderId,
            'tag_ids': n.tagIds,
            'created_at': n.createdAt.millisecondsSinceEpoch,
            'updated_at': n.updatedAt.millisecondsSinceEpoch,
          }).toList();
        }
        if (folders.isNotEmpty) {
          data['note_folders'] = folders.map((f) => f.toMap()).toList();
        }
        if (tags.isNotEmpty) {
          data['note_tags'] = tags.map((t) => t.toMap()).toList();
        }
        content = const JsonEncoder.withIndent('  ').convert(data);
      }

      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'aawara_fullbackup_$stamp.json';
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/$fileName');
      await file.writeAsString(content, encoding: utf8);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Aawara Full Backup',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingFullBackup = false);
    }
  }

  // ─── Import ───────────────────────────────────────────────────────────────

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read file.'),
          backgroundColor: Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final jsonStr = String.fromCharCodes(bytes);
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Invalid JSON file. Please pick an Aawara export.'),
          backgroundColor: Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final count =
        (parsed['workouts'] as List? ?? []).length;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import Workouts',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Found $count workout${count == 1 ? '' : 's'} in this file.\n\n'
          'Workouts on dates that already have an entry will be skipped. '
          'This will not overwrite any existing data.',
          style: const TextStyle(color: Color(0xFFCCCCDD), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import',
                style: TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _importing = true);
    try {
      final (:imported, :skipped) = await _db.importFromJson(jsonStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$imported workout${imported == 1 ? '' : 's'} imported'
              '${skipped > 0 ? ', $skipped skipped (date conflict)' : ''}'),
          backgroundColor: const Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
        ));
        _refreshPreview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ─── CSV builder ──────────────────────────────────────────────────────────

  String _buildCsv(List<WorkoutLog> logs, Map<String, Exercise> exMap) {
    final sb = StringBuffer();
    sb.writeln(
        'date,workout_name,completed,exercise_name,muscle_group,equipment,set_number,weight_kg,reps');
    for (final log in logs) {
      for (final exLog in log.exercises) {
        final ex = exMap[exLog.exerciseId];
        final exName = _csvEsc(ex?.name ?? exLog.exerciseId);
        final muscle = ex?.muscleGroup ?? '';
        final equip = ex?.equipment ?? '';
        if (exLog.sets.isEmpty) {
          sb.writeln(
              '${log.date},${_csvEsc(log.workoutName)},${log.completed},$exName,$muscle,$equip,,,');
        } else {
          for (final s in exLog.sets) {
            sb.writeln(
                '${log.date},${_csvEsc(log.workoutName)},${log.completed},$exName,$muscle,$equip,${s.setNumber},${s.weight ?? ''},${s.reps ?? ''}');
          }
        }
      }
    }
    return sb.toString();
  }

  String _csvEsc(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  // ─── JSON builder ─────────────────────────────────────────────────────────

  Future<String> _buildJson(
    List<WorkoutLog> logs,
    Map<String, Exercise> exMap,
    Set<_DataCategory> cats,
    String from,
    String to,
  ) async {
    final db = await _db.database;
    bool has(c) => cats.contains(c);

    // Fetch additional data per selected category
    List<Map<String, dynamic>> prs = [];
    if (has(_DataCategory.personalRecords)) {
      prs = await db.rawQuery('''
        SELECT ep.best_1rm, ep.date, e.name
        FROM exercise_prs ep JOIN exercises e ON e.id = ep.exercise_id
        WHERE ep.date >= ? AND ep.date <= ?
        ORDER BY ep.best_1rm DESC
      ''', [from, to]);
    }

    List<DailyNutritionSummary> nutritionData = [];
    if (has(_DataCategory.nutrition)) {
      nutritionData = await _db.getNutritionHistory(from, to);
    }

    List<Map<String, dynamic>> nutritionGoals = [];
    if (has(_DataCategory.nutritionGoals)) {
      nutritionGoals = await db.query('nutrition_goals', limit: 1);
    }

    List<Map<String, dynamic>> weightData = [];
    if (has(_DataCategory.bodyWeight)) {
      weightData = await db.query('body_weight_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
    }

    List<Map<String, dynamic>> waterData = [];
    if (has(_DataCategory.water)) {
      waterData = await db.query('water_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
    }

    List<Map<String, dynamic>> wellnessData = [];
    if (has(_DataCategory.wellness)) {
      wellnessData = await db.query('wellness_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
    }

    List<Map<String, dynamic>> stepData = [];
    if (has(_DataCategory.stepLogs)) {
      stepData = await db.query('step_logs',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC');
    }

    List<Map<String, dynamic>> measurementData = [];
    if (has(_DataCategory.bodyMeasurements)) {
      measurementData = await db.query('body_measurements',
          where: 'date >= ? AND date <= ?',
          whereArgs: [from, to],
          orderBy: 'date ASC, type ASC');
    }

    final payload = <String, dynamic>{
      'app': 'aawara',
      'schema_version': 3,
      'exported_at': DateTime.now().toIso8601String(),
      'date_range': {'from': from, 'to': to},
      'exercise_filter': _filterExercise?.name ?? 'All',
      if (has(_DataCategory.workouts)) ...{
        'total_workouts': logs.length,
        'total_sets': logs.fold(0, (s, l) => s + l.totalSets),
        'workouts': logs.map((log) => {
          'date': log.date,
          'workout_name': log.workoutName,
          'completed': log.completed,
          if (log.durationSeconds != null) 'duration_seconds': log.durationSeconds,
          'total_volume_kg': log.totalVolume,
          'exercises': log.exercises.map((exLog) {
            final ex = exMap[exLog.exerciseId];
            return {
              'name': ex?.name ?? exLog.exerciseId,
              'muscle_group': ex?.muscleGroup ?? '',
              'equipment': ex?.equipment ?? '',
              'exercise_type': ex?.exerciseType ?? 'strength',
              if (exLog.notes != null && exLog.notes!.isNotEmpty) 'note': exLog.notes,
              'sets': exLog.sets.map((s) => {
                'set_number': s.setNumber,
                'is_completed': s.isCompleted,
                if (s.weight != null) 'weight_kg': s.weight,
                if (s.reps != null) 'reps': s.reps,
                if (s.durationSeconds != null) 'duration_seconds': s.durationSeconds,
                if (s.speed != null) 'speed': s.speed,
                if (s.incline != null) 'incline': s.incline,
                if (s.resistance != null) 'resistance': s.resistance,
                if (s.distanceKm != null) 'distance_km': s.distanceKm,
              }).toList(),
            };
          }).toList(),
        }).toList(),
      },
      if (prs.isNotEmpty) 'personal_records': prs.map((pr) => {
        'exercise': pr['name'],
        'best_1rm_kg': pr['best_1rm'],
        'date': pr['date'],
      }).toList(),
      if (nutritionGoals.isNotEmpty) 'nutrition_goals': {
        'calories': nutritionGoals.first['calories'],
        'protein_g': nutritionGoals.first['protein_g'],
        'carbs_g': nutritionGoals.first['carbs_g'],
        'fat_g': nutritionGoals.first['fat_g'],
      },
      if (nutritionData.isNotEmpty) 'nutrition_daily': nutritionData.map((n) => {
        'date': n.date,
        'calories': n.calories.round(),
        'protein_g': double.parse(n.proteinG.toStringAsFixed(1)),
        'carbs_g': double.parse(n.carbsG.toStringAsFixed(1)),
        'fat_g': double.parse(n.fatG.toStringAsFixed(1)),
      }).toList(),
      if (weightData.isNotEmpty) 'body_weight': weightData.map((r) => {
        'date': r['date'],
        'weight_kg': r['weight_kg'],
        if (r['notes'] != null) 'notes': r['notes'],
      }).toList(),
      if (waterData.isNotEmpty) 'water_intake': waterData.map((r) => {
        'date': r['date'],
        'glasses_drunk': r['glasses_drunk'],
        'target_glasses': r['target_glasses'],
        'litres': ((r['glasses_drunk'] as int) * 0.25),
      }).toList(),
      if (wellnessData.isNotEmpty) 'wellness': wellnessData.map((r) => {
        'date': r['date'],
        'sleep_hours': r['sleep_hours'],
        'energy': r['energy'],
        'soreness': r['soreness'],
        if (r['notes'] != null) 'notes': r['notes'],
      }).toList(),
      if (stepData.isNotEmpty) 'step_logs': stepData.map((r) => {
        'date': r['date'],
        'steps': r['steps'],
        'goal': r['goal'],
      }).toList(),
      if (measurementData.isNotEmpty) 'body_measurements': measurementData.map((r) => {
        'date': r['date'],
        'type': r['type'],
        'value_cm': r['value_cm'],
      }).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ─── Exercise picker ──────────────────────────────────────────────────────

  Future<void> _pickExercise() async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExercisePicker(),
    );
    if (picked != null || picked == null) {
      // picked == null means "clear" was tapped inside the picker via a separate path
    }
    if (!mounted) return;
    setState(() => _filterExercise = picked);
    _refreshPreview();
  }

  // ─── Date pickers ─────────────────────────────────────────────────────────

  Future<void> _pickCustomDate({required bool isFrom}) async {
    final initial = isFrom ? _customFrom : _customTo;
    final first = DateTime(2020);
    final last = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: first,
      lastDate: last,
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
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _customFrom = picked;
        if (_customTo.isBefore(_customFrom)) _customTo = _customFrom;
      } else {
        _customTo = picked;
        if (_customFrom.isAfter(_customTo)) _customFrom = _customTo;
      }
    });
    _refreshPreview();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Export / Import',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _importing ? null : _import,
            icon: _importing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF2ECC71)),
                  )
                : const Icon(Icons.upload_file_rounded,
                    color: Color(0xFF2ECC71), size: 18),
            label: Text(
              _importing ? 'Importing…' : 'Restore',
              style: const TextStyle(
                  color: Color(0xFF2ECC71), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _sectionLabel('DATE RANGE'),
          _buildRangeChips(),
          if (_range == _Range.custom) _buildCustomDateRow(),
          const SizedBox(height: 20),
          _sectionLabel('EXERCISE FILTER'),
          _buildExerciseFilter(),
          const SizedBox(height: 20),
          _sectionLabel('FORMAT'),
          _buildFormatToggle(),
          const SizedBox(height: 20),
          _buildPreviewCard(),
          const SizedBox(height: 28),
          _sectionLabel('AI ANALYSIS'),
          _buildAIExportCard(),
          const SizedBox(height: 28),
          _sectionLabel('FULL BACKUP'),
          _buildFullBackupCard(),
          const SizedBox(height: 28),
          _sectionLabel('RESTORE FROM BACKUP'),
          _buildImportCard(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _exporting ? null : _export,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _exporting
                            ? [const Color(0xFF888866), const Color(0xFF666644)]
                            : [const Color(0xFFFFD700), const Color(0xFFFFA500)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_exporting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black54),
                          )
                        else
                          const Icon(Icons.ios_share_rounded,
                              color: Colors.black, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _exporting ? 'Preparing…' : 'Export File',
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF888899),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      );

  // ─── AI export card ──────────────────────────────────────────────────────

  Widget _buildAIExportCard() {
    return GestureDetector(
      onTap: _exportingAI ? null : _exportForAI,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _exportingAI
                ? const Color(0xFF333355)
                : const Color(0xFF9B59B6).withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: _exportingAI
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF9B59B6), Color(0xFF6C3483)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: _exportingAI ? const Color(0xFF1A1A2E) : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _exportingAI
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF9B59B6)),
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export to AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Generates a Markdown file with all your workouts, nutrition, wellness & PRs — paste into ChatGPT, Gemini, or Claude for personalised insights',
                    style: TextStyle(color: Color(0xFF555577), fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.auto_awesome_rounded,
                color: Color(0xFF9B59B6), size: 16),
          ],
        ),
      ),
    );
  }

  // ─── Full backup card ─────────────────────────────────────────────────────

  Widget _buildFullBackupCard() {
    return GestureDetector(
      onTap: _exportingFullBackup ? null : _exportFullBackup,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _exportingFullBackup
                ? const Color(0xFF333355)
                : const Color(0xFF3498DB).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF3498DB).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _exportingFullBackup
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF3498DB)),
                      ),
                    )
                  : const Icon(Icons.backup_rounded,
                      color: Color(0xFF3498DB), size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Full Backup',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Exports everything: workouts, nutrition, water, custom foods & more',
                    style: TextStyle(color: Color(0xFF555577), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.ios_share_rounded,
                color: Color(0xFF3498DB), size: 18),
          ],
        ),
      ),
    );
  }

  // ─── Import card ─────────────────────────────────────────────────────────

  Widget _buildImportCard() {
    return GestureDetector(
      onTap: _importing ? null : _import,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _importing
                ? const Color(0xFF333355)
                : const Color(0xFF2ECC71).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _importing
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF2ECC71)),
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded,
                      color: Color(0xFF2ECC71), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _importing ? 'Importing…' : 'Restore from Backup',
                    style: TextStyle(
                      color: _importing ? const Color(0xFF555577) : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Pick a JSON file exported from Aawara',
                    style: TextStyle(color: Color(0xFF555577), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF444466), size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Range chips ──────────────────────────────────────────────────────────

  static const _rangeLabels = {
    _Range.today: 'Today',
    _Range.week: 'This Week',
    _Range.month: 'This Month',
    _Range.year: 'This Year',
    _Range.all: 'All Time',
    _Range.custom: 'Custom',
  };

  Widget _buildRangeChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _Range.values.map((r) {
        final selected = _range == r;
        return GestureDetector(
          onTap: () {
            setState(() => _range = r);
            _refreshPreview();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                    : const Color(0xFF333355),
              ),
            ),
            child: Text(
              _rangeLabels[r]!,
              style: TextStyle(
                color: selected ? const Color(0xFFFFD700) : const Color(0xFF888899),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomDateRow() {
    final fmt = DateFormat('MMM d, yyyy');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: _DateButton(
              label: 'From',
              value: fmt.format(_customFrom),
              onTap: () => _pickCustomDate(isFrom: true),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward, color: Color(0xFF555577), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: _DateButton(
              label: 'To',
              value: fmt.format(_customTo),
              onTap: () => _pickCustomDate(isFrom: false),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Exercise filter ──────────────────────────────────────────────────────

  Widget _buildExerciseFilter() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _RadioRow(
            label: 'All Exercises',
            subtitle: 'Export every exercise in the selected period',
            selected: _filterExercise == null,
            onTap: () {
              if (_filterExercise != null) {
                setState(() => _filterExercise = null);
                _refreshPreview();
              }
            },
          ),
          const Divider(color: Color(0xFF1E1E35), height: 1, indent: 16),
          _RadioRow(
            label: _filterExercise?.name ?? 'Specific Exercise',
            subtitle: _filterExercise != null
                ? '${_filterExercise!.muscleGroup} · ${_filterExercise!.equipment}'
                : 'Choose one exercise to export',
            selected: _filterExercise != null,
            onTap: _pickExercise,
            trailing: _filterExercise != null
                ? GestureDetector(
                    onTap: () {
                      setState(() => _filterExercise = null);
                      _refreshPreview();
                    },
                    child: const Icon(Icons.close,
                        color: Color(0xFF555577), size: 16),
                  )
                : const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF555577), size: 18),
          ),
        ],
      ),
    );
  }

  // ─── Format toggle ────────────────────────────────────────────────────────

  Widget _buildFormatToggle() {
    return Row(
      children: _Format.values.map((f) {
        final selected = _format == f;
        final label = f == _Format.csv ? 'CSV' : 'JSON';
        final desc = f == _Format.csv
            ? 'Spreadsheet-friendly'
            : 'Structured / developer';
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _format = f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: EdgeInsets.only(right: f == _Format.csv ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFFD700).withValues(alpha: 0.1)
                    : const Color(0xFF12121F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                      : const Color(0xFF1E1E35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        f == _Format.csv
                            ? Icons.table_chart_rounded
                            : Icons.data_object_rounded,
                        color: selected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF888899),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? const Color(0xFFFFD700) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (selected)
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFFFFD700), size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Preview card ─────────────────────────────────────────────────────────

  Widget _buildPreviewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: _loadingPreview
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFFD700)),
                ),
              ),
            )
          : Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFF555577), size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _previewWorkouts == 0
                        ? 'No workouts found for the selected range'
                        : '${_previewWorkouts ?? 0} workout${(_previewWorkouts ?? 0) == 1 ? '' : 's'} · '
                            '${_previewSets ?? 0} set${(_previewSets ?? 0) == 1 ? '' : 's'} '
                            'will be exported as ${_format == _Format.csv ? 'CSV' : 'JSON'}',
                    style: const TextStyle(
                        color: Color(0xFF888899), fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Category picker sheet ────────────────────────────────────────────────────

class _CategoryPickerSheet extends StatefulWidget {
  final List<_DataCategory> available;
  final Set<_DataCategory> initial;
  final String title;

  const _CategoryPickerSheet({
    required this.available,
    required this.initial,
    required this.title,
  });

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late Set<_DataCategory> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == widget.available.length;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (ctx, scrollCtrl) => Container(
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_selected.length} of ${widget.available.length} selected',
                          style: const TextStyle(
                              color: Color(0xFF888899), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected = Set.from(widget.available);
                      }
                    }),
                    child: Text(
                      allSelected ? 'Deselect All' : 'Select All',
                      style: const TextStyle(color: Color(0xFFFFD700)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E1E35), height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                itemCount: widget.available.length,
                itemBuilder: (ctx, i) {
                  final cat = widget.available[i];
                  final info = _catInfo[cat]!;
                  final isSelected = _selected.contains(cat);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (isSelected) {
                        _selected.remove(cat);
                      } else {
                        _selected.add(cat);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFFD700).withValues(alpha: 0.4)
                              : const Color(0xFF2A2A3E),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(info.emoji,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  info.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFFCCCCDD),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  info.desc,
                                  style: const TextStyle(
                                      color: Color(0xFF555577), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFFD700)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFF444466),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.black, size: 14)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, Set<_DataCategory>.from(_selected)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF2A2A3E),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    _selected.isEmpty
                        ? 'Select at least one category'
                        : 'Continue with ${_selected.length} selected',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
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

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF333355)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF888899),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.calendar_today_rounded,
                    color: Color(0xFFFFD700), size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _RadioRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF444466),
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          selected ? Colors.white : const Color(0xFFA8A8B3),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF555577), fontSize: 11)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ─── Exercise picker bottom sheet ─────────────────────────────────────────────

class _ExercisePicker extends StatefulWidget {
  const _ExercisePicker();

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  final _db = WorkoutDatabase.instance;
  final _searchCtrl = TextEditingController();
  List<Exercise> _all = [];
  List<Exercise> _filtered = [];
  String? _group;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await _db.getAllExercises();
    if (mounted) {
      setState(() {
        _all = all;
        _filter();
      });
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((e) {
        final matchQ = e.name.toLowerCase().contains(q);
        final matchG = _group == null || e.muscleGroup == _group;
        return matchQ && matchG;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
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
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF444466),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
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
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
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
            // Muscle group filter
            MuscleGroupFilter(
              selected: _group,
              onChanged: (g) => setState(() {
                _group = g;
                _filter();
              }),
            ),
            const SizedBox(height: 6),
            // List
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Color(0xFF1A1A2E), height: 1),
                itemBuilder: (_, i) {
                  final ex = _filtered[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
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
