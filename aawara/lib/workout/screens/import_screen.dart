import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../database/workout_database.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _picking = false;
  bool _importing = false;
  _ImportResult? _result;

  Future<void> _startImport() async {
    // Step 1: warning dialog
    final confirmed = await _showWarningDialog();
    if (!confirmed || !mounted) return;

    // Step 2: pick file
    setState(() => _picking = true);
    PlatformFile? file;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      file = result.files.first;
    } catch (e) {
      setState(() => _picking = false);
      _showError('Could not open file picker: $e');
      return;
    }

    // Step 3: parse + import
    setState(() { _picking = false; _importing = true; _result = null; });

    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _importing = false);
      _showError('Could not read file contents.');
      return;
    }

    String jsonStr;
    try {
      jsonStr = utf8.decode(bytes);
    } catch (_) {
      setState(() => _importing = false);
      _showError('File is not valid UTF-8 text.');
      return;
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _importing = false);
      _showError(
          'Invalid JSON. Please select an Aawara export file (.json).');
      return;
    }

    // Step 4: run import
    try {
      final schemaVersion = parsed['schema_version'] as int? ?? 1;

      if (schemaVersion >= 3) {
        // Full backup — use the comprehensive import method
        final counts = await WorkoutDatabase.instance.importFullBackup(jsonStr);
        if (mounted) {
          setState(() {
            _importing = false;
            _result = _ImportResult.fromFullBackup(counts);
          });
        }
      } else {
        // Legacy workout-only export
        final (:imported, :skipped) =
            await WorkoutDatabase.instance.importFromJson(jsonStr);

        int bwImported = 0;
        int bwSkipped = 0;
        final bwLogs = (parsed['body_weight_logs'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        for (final bw in bwLogs) {
          final date = bw['date'] as String? ?? '';
          final weightKg = (bw['weight_kg'] as num?)?.toDouble();
          if (date.isEmpty || weightKg == null) {
            bwSkipped++;
            continue;
          }
          final existing = await WorkoutDatabase.instance
              .getBodyWeightLogs(fromDate: date, toDate: date);
          if (existing.isNotEmpty) {
            bwSkipped++;
          } else {
            await WorkoutDatabase.instance.logBodyWeight(date, weightKg);
            bwImported++;
          }
        }

        if (mounted) {
          setState(() {
            _importing = false;
            _result = _ImportResult(
              isFullBackup: false,
              rows: {
                'Workouts': (imported: imported, skipped: skipped),
                'Body weight entries': (imported: bwImported, skipped: bwSkipped),
              },
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        _showError('Import failed: $e');
      }
    }
  }

  Future<bool> _showWarningDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Before you import',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will merge imported data with your existing data.\n\n'
          '• Existing entries are never overwritten or deleted\n'
          '• Duplicate dates/IDs are skipped automatically\n'
          '• Full backups restore workouts, nutrition, water, custom foods, wellness & more\n\n'
          'Continue?',
          style: TextStyle(color: Color(0xFFCCCCDD), height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFFE74C3C),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Import Data',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(18),
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
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.download_rounded,
                            color: Color(0xFF2ECC71), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Restore from Backup',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Select an Aawara export file (.json) to import. '
                    'Your data is merged safely — existing entries are never overwritten.',
                    style: TextStyle(
                        color: Color(0xFF888899), fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  _infoRow(Icons.check_circle_outline_rounded,
                      'Full backups restore workouts, nutrition, water logs, custom foods, meal presets, wellness & more'),
                  _infoRow(Icons.check_circle_outline_rounded,
                      'Exercises and foods matched by name — no duplicates'),
                  _infoRow(Icons.info_outline_rounded,
                      'Entries on duplicate dates / existing IDs are skipped'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Result card (shown after import)
            if (_result != null) _buildResultCard(_result!),
            if (_result != null) const SizedBox(height: 24),

            // Import button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_picking || _importing) ? null : _startImport,
                icon: _picking || _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 20),
                label: Text(
                  _picking
                      ? 'Selecting file…'
                      : _importing
                          ? 'Importing…'
                          : _result != null
                              ? 'Import Another File'
                              : 'Select JSON File',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFFFFD700).withValues(alpha: 0.5),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF555577), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFF666688), fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(_ImportResult r) {
    final totalImported = r.rows.values.fold(0, (s, v) => s + v.imported);
    final hasData = totalImported > 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasData
              ? const Color(0xFF2ECC71).withValues(alpha: 0.4)
              : const Color(0xFF1E1E35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasData
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: hasData
                    ? const Color(0xFF2ECC71)
                    : const Color(0xFF888899),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasData
                      ? r.isFullBackup
                          ? 'Full Backup Restored'
                          : 'Import Complete'
                      : 'Nothing New to Import',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in r.rows.entries) ...[
            if (entry.value.imported > 0)
              _resultRow('${entry.key} imported', entry.value.imported),
            if (entry.value.skipped > 0)
              _resultRow('${entry.key} skipped', entry.value.skipped, dim: true),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(String label, int count, {bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: dim
                        ? const Color(0xFF555577)
                        : const Color(0xFF888899),
                    fontSize: 13)),
          ),
          Text('$count',
              style: TextStyle(
                  color: dim
                      ? const Color(0xFF555577)
                      : const Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ImportResult {
  final bool isFullBackup;
  final Map<String, ({int imported, int skipped})> rows;

  const _ImportResult({
    required this.isFullBackup,
    required this.rows,
  });

  factory _ImportResult.fromFullBackup(
      Map<String, ({int imported, int skipped})> counts) {
    const labels = {
      'custom_exercises': 'Custom exercises',
      'custom_foods': 'Custom foods',
      'workout_logs': 'Workouts',
      'body_weight_logs': 'Body weight entries',
      'nutrition_logs': 'Nutrition entries',
      'water_logs': 'Water logs',
      'meal_presets': 'Meal presets',
      'wellness_logs': 'Wellness logs',
      'achievements': 'Achievements',
      'exercise_prs': 'Exercise PRs',
      'nutrition_goals': 'Nutrition goals',
      'day_overrides': 'Day overrides',
      'quick_start_templates': 'Quick start templates',
    };
    final rows = <String, ({int imported, int skipped})>{};
    for (final k in labels.keys) {
      if (counts.containsKey(k)) {
        rows[labels[k]!] = counts[k]!;
      }
    }
    return _ImportResult(isFullBackup: true, rows: rows);
  }
}
