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

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _Range { today, week, month, year, all, custom }

enum _Format { json, csv }

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

  // ─── Export ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final (from, to) = _fromTo;
      final logs = await _db.getWorkoutLogsForExport(
        fromDate: from,
        toDate: to,
        exerciseId: _filterExercise?.id,
      );

      // Build exercise name lookup
      final exerciseMap = <String, Exercise>{};
      for (final log in logs) {
        for (final exLog in log.exercises) {
          if (!exerciseMap.containsKey(exLog.exerciseId)) {
            final ex = await _db.getExerciseById(exLog.exerciseId);
            if (ex != null) exerciseMap[exLog.exerciseId] = ex;
          }
        }
      }

      List<DailyNutritionSummary> nutritionData = [];
      if (_format == _Format.json) {
        nutritionData = await _db.getNutritionHistory(from, to);
      }

      final content = _format == _Format.csv
          ? _buildCsv(logs, exerciseMap)
          : _buildJson(logs, exerciseMap, nutritionData, from, to);

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

  String _buildJson(
    List<WorkoutLog> logs,
    Map<String, Exercise> exMap,
    List<DailyNutritionSummary> nutrition,
    String from,
    String to,
  ) {
    final payload = {
      'app': 'aawara',
      'schema_version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'date_range': {'from': from, 'to': to},
      'exercise_filter': _filterExercise?.name ?? 'All',
      'total_workouts': logs.length,
      'total_sets': logs.fold(0, (s, l) => s + l.totalSets),
      if (nutrition.isNotEmpty)
        'nutrition_daily': nutrition
            .map((n) => {
                  'date': n.date,
                  'calories': n.calories.round(),
                  'protein_g': double.parse(n.proteinG.toStringAsFixed(1)),
                  'carbs_g': double.parse(n.carbsG.toStringAsFixed(1)),
                  'fat_g': double.parse(n.fatG.toStringAsFixed(1)),
                })
            .toList(),
      'workouts': logs
          .map((log) => {
                'date': log.date,
                'workout_name': log.workoutName,
                'completed': log.completed,
                if (log.durationSeconds != null)
                  'duration_seconds': log.durationSeconds,
                'total_volume_kg': log.totalVolume,
                'exercises': log.exercises
                    .map((exLog) {
                      final ex = exMap[exLog.exerciseId];
                      return {
                        'name': ex?.name ?? exLog.exerciseId,
                        'muscle_group': ex?.muscleGroup ?? '',
                        'equipment': ex?.equipment ?? '',
                        'exercise_type': ex?.exerciseType ?? 'strength',
                        'sets': exLog.sets
                            .map((s) => {
                                  'set_number': s.setNumber,
                                  'is_completed': s.isCompleted,
                                  if (s.weight != null) 'weight_kg': s.weight,
                                  if (s.reps != null) 'reps': s.reps,
                                  if (s.durationSeconds != null)
                                    'duration_seconds': s.durationSeconds,
                                  if (s.speed != null) 'speed': s.speed,
                                  if (s.incline != null) 'incline': s.incline,
                                  if (s.resistance != null)
                                    'resistance': s.resistance,
                                  if (s.distanceKm != null)
                                    'distance_km': s.distanceKm,
                                })
                            .toList(),
                      };
                    })
                    .toList(),
              })
          .toList(),
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
