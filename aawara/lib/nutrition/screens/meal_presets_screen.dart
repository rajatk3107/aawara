import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

class MealPresetsScreen extends StatefulWidget {
  /// If provided, tapping a preset will log it to this date + show meal picker.
  final String? logToDate;

  const MealPresetsScreen({super.key, this.logToDate});

  @override
  State<MealPresetsScreen> createState() => _MealPresetsScreenState();
}

class _MealPresetsScreenState extends State<MealPresetsScreen> {
  final _db = WorkoutDatabase.instance;
  List<MealPreset> _presets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await _db.getMealPresets();
    if (mounted) setState(() { _presets = p; _loading = false; });
  }

  Future<void> _delete(MealPreset preset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Preset',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Delete "${preset.name}"?',
            style: const TextStyle(color: Color(0xFF888899))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF888899)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFE74C3C)))),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteMealPreset(preset.id);
      _load();
    }
  }

  Future<void> _log(MealPreset preset) async {
    if (widget.logToDate == null) return;
    const meals = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
    final meal = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log "${preset.name}" to…',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...meals.map((m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(_mealIcon(m),
                      style: const TextStyle(fontSize: 20)),
                  title: Text(m,
                      style: const TextStyle(
                          color: Color(0xFFCCCCDD), fontSize: 15)),
                  subtitle: m == meals.first
                      ? Text(
                          '${preset.items.length} items · '
                          '${preset.totalCalories.round()} kcal',
                          style: const TextStyle(
                              color: Color(0xFF555577), fontSize: 12))
                      : null,
                  onTap: () => Navigator.pop(context, m),
                )),
          ],
        ),
      ),
    );
    if (meal == null || !mounted) return;
    await _db.logMealPreset(preset.id, widget.logToDate!, meal);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context, true); // signal that we logged something
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
        title: const Text('Saved Meals',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : _presets.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: _presets.length,
                  itemBuilder: (_, i) => _buildPresetCard(_presets[i]),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_outline_rounded,
              color: Color(0xFF333355), size: 52),
          const SizedBox(height: 14),
          const Text('No saved meals yet',
              style: TextStyle(color: Color(0xFF888899), fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Log a meal and tap the bookmark icon\nto save it as a preset.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF444466), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(MealPreset preset) {
    return Dismissible(
      key: Key(preset.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE74C3C).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFE74C3C)),
      ),
      confirmDismiss: (_) async {
        await _delete(preset);
        return false; // we manage deletion ourselves in _delete
      },
      child: GestureDetector(
        onTap: widget.logToDate != null ? () => _log(preset) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
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
                  const Icon(Icons.bookmark_rounded,
                      color: Color(0xFFFFD700), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(preset.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (widget.logToDate != null)
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF333355), size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: preset.items.take(4).map((item) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D1A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.food.name,
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 11),
                    ),
                  );
                }).toList()
                  ..addAll(preset.items.length > 4
                      ? [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0D1A),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${preset.items.length - 4} more',
                              style: const TextStyle(
                                  color: Color(0xFF555577), fontSize: 11),
                            ),
                          )
                        ]
                      : []),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _chip('${preset.totalCalories.round()} kcal',
                      const Color(0xFFFFD700)),
                  const SizedBox(width: 8),
                  _chip('P ${preset.totalProtein.toStringAsFixed(1)}g',
                      const Color(0xFF3498DB)),
                  const SizedBox(width: 8),
                  Text('${preset.items.length} foods',
                      style: const TextStyle(
                          color: Color(0xFF444466), fontSize: 11)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _delete(preset),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFF333355), size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Text(text,
      style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w600));

  String _mealIcon(String meal) {
    switch (meal) {
      case 'Breakfast': return '🌅';
      case 'Lunch': return '☀️';
      case 'Dinner': return '🌙';
      default: return '🍎';
    }
  }
}
