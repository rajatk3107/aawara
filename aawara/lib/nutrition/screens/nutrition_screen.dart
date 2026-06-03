import 'package:flutter/material.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../../workout/widgets/step_counter_card.dart';
import '../../utils/safe_navigation.dart';
import '../widgets/add_food_sheet.dart';
import '../widgets/edit_food_entry_sheet.dart';
import '../widgets/meal_picker_sheet.dart';
import '../widgets/water_tracker_card.dart';
import 'meal_presets_screen.dart';
import 'nutrition_goals_screen.dart';
import 'tdee_calculator_screen.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _db = WorkoutDatabase.instance;

  DateTime _selectedDate = DateTime.now();
  NutritionTotals _totals = NutritionTotals.empty;
  NutritionGoals _goals = NutritionGoals.defaults;
  Map<String, String> _mealNames = {};
  List<String> _activeMealKeys = [];
  bool _loading = true;

  static const _defaultMealNames = {
    'meal_1': 'Meal 1',
    'meal_2': 'Meal 2',
    'meal_3': 'Meal 3',
    'meal_4': 'Meal 4',
    'meal_5': 'Meal 5',
  };

  String _displayName(String key) =>
      _mealNames[key] ?? _defaultMealNames[key] ?? key;

  static const _mealIcons = {
    'meal_1': '🌅',
    'meal_2': '☀️',
    'meal_3': '🌙',
    'meal_4': '🍎',
    'meal_5': '🌃',
  };

  String _iconForKey(String key) => _mealIcons[key] ?? '🍽️';

  String get _dateStr {
    final d = _selectedDate;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get _isToday {
    final n = DateTime.now();
    return _selectedDate.year == n.year &&
        _selectedDate.month == n.month &&
        _selectedDate.day == n.day;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _db.getFoodsForDate(_dateStr),
      _db.getNutritionGoals(),
      _db.getMealTemplates(),
      _db.getMealSlotKeys(),
    ]);
    if (!mounted) return;
    final templates = results[2] as Map<String, String>;
    final slotKeys = results[3] as List<String>;
    setState(() {
      _totals = results[0] as NutritionTotals;
      _goals = (results[1] as NutritionGoals?) ?? NutritionGoals.defaults;
      _activeMealKeys = slotKeys;
      _mealNames = {
        for (final key in slotKeys)
          key: templates[key] ?? _defaultMealNames[key] ?? _labelFromKey(key)
      };
      _loading = false;
    });
  }

  String _labelFromKey(String key) {
    final num = key.replaceAll('meal_', '');
    return 'Meal $num';
  }

  void _prevDay() {
    setState(() { _selectedDate = _selectedDate.subtract(const Duration(days: 1)); _loading = true; });
    _load();
  }

  void _nextDay() {
    if (_isToday) return;
    setState(() { _selectedDate = _selectedDate.add(const Duration(days: 1)); _loading = true; });
    _load();
  }

  Future<void> _copyMealFromYesterday(String mealKey, String displayName) async {
    final yesterday = _selectedDate.subtract(const Duration(days: 1));
    final fromStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final count = await _db.copyMealEntries(
      fromDate: fromStr,
      toDate: _dateStr,
      mealType: mealKey,
    );
    if (!mounted) return;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No items logged in $displayName yesterday'),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Copied $count item${count == 1 ? '' : 's'} from yesterday'),
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    _load();
  }

  Future<void> _deleteMeal(String mealKey, String displayName) async {
    final entries = _totals.entries.where((e) => e.mealType == mealKey).toList();
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$displayName is already empty'),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete $displayName?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove all ${entries.length} item${entries.length == 1 ? '' : 's'} from $displayName?',
          style: const TextStyle(color: Color(0xFF888899)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all', style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteMealEntries(_dateStr, mealKey);
      _load();
    }
  }

  Future<void> _deleteEntry(NutritionEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Remove entry?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${e.food.name} from your log?',
          style: const TextStyle(color: Color(0xFF888899)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteNutritionEntry(e.id);
      _load();
    }
  }

  Future<void> _editEntry(NutritionEntry e) async {
    final changed = await showEditFoodEntrySheet(
      context,
      entry: e,
      mealNames: _mealNames,
      defaultMealNames: _defaultMealNames,
      mealKeys: _activeMealKeys,
    );
    if (changed == true) _load();
  }

  Future<void> _moveEntry(NutritionEntry e) async {
    final current = e.mealType;
    String? picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Move to meal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _activeMealKeys.map((key) {
            final isSelected = key == current;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(_mealIcons[key]!, style: const TextStyle(fontSize: 20)),
              title: Text(
                _displayName(key),
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFFD700) : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected ? const Icon(Icons.check_rounded, color: Color(0xFFFFD700), size: 18) : null,
              onTap: () => Navigator.pop(ctx, key),
            );
          }).toList(),
        ),
      ),
    );
    if (picked != null && picked != current) {
      await _db.updateNutritionEntry(e.id, mealType: picked);
      _load();
    }
  }

  Future<void> _showAddFood({required String mealKey}) async {
    final added = await showAddFoodSheet(
      context,
      date: _dateStr,
      meal: mealKey,
      mealDisplayName: _displayName(mealKey),
    );
    if (added) _load();
  }

  Future<void> _pickMealThenAddFood() async {
    final picked = await showMealPickerSheet(
      context,
      mealNames: _mealNames,
      defaultMealNames: _defaultMealNames,
      mealKeys: _activeMealKeys,
      mealIcons: {for (final k in _activeMealKeys) k: _iconForKey(k)},
    );
    if (picked == null || !mounted) return;
    // Reload if a new meal was created (new key not previously in list)
    if (!_activeMealKeys.contains(picked)) await _load();
    if (!mounted) return;
    await _showAddFood(mealKey: picked);
  }

  Future<void> _deleteMealSlot(String mealKey, String displayName) async {
    if (_activeMealKeys.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('At least one meal must remain'),
        backgroundColor: const Color(0xFF1A1A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final entryCount = _totals.entries.where((e) => e.mealType == mealKey).length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete $displayName?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          entryCount > 0
              ? 'This will permanently remove $displayName and all $entryCount food log entries across all dates.'
              : 'This will permanently remove $displayName.',
          style: const TextStyle(color: Color(0xFF888899), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete meal',
                style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteMealSlot(mealKey);
      _load();
    }
  }

  Future<void> _renameMeal(String mealKey) async {
    final ctrl = TextEditingController(text: _displayName(mealKey));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename meal',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: _defaultMealNames[mealKey] ?? 'Meal name',
            hintStyle: const TextStyle(color: Color(0xFF444466)),
            filled: true,
            fillColor: const Color(0xFF0D0D1A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFFD700))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => popAfterFocusSettles(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              popAfterFocusSettles(ctx, v.isNotEmpty ? v : null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    await _db.saveMealTemplate(mealKey, name);
    setState(() => _mealNames[mealKey] = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      resizeToAvoidBottomInset: false,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: const Color(0xFF0D0D1A),
            foregroundColor: Colors.white,
            floating: true,
            snap: true,
            elevation: 0,
            title: const Text('Nutrition',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_outline_rounded, color: Color(0xFF888899)),
                tooltip: 'Saved Meals',
                onPressed: _openPresets,
              ),
              IconButton(
                icon: const Icon(Icons.calculate_rounded, color: Color(0xFF888899)),
                tooltip: 'TDEE Calculator',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TdeeCalculatorScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.track_changes_rounded, color: Color(0xFF888899)),
                tooltip: 'Set Goals',
                onPressed: _openGoals,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: _buildDateStrip(),
            ),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
            : RefreshIndicator(
                color: const Color(0xFFFFD700),
                backgroundColor: const Color(0xFF1A1A2E),
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: [
                    _buildMacroSummary(),
                    const SizedBox(height: 12),
                    WaterTrackerCard(date: _dateStr),
                    const SizedBox(height: 12),
                    StepCounterCard(date: _dateStr),
                    const SizedBox(height: 12),
                    ..._activeMealKeys.map(_buildMealSection),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickMealThenAddFood,
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Food', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDateStrip() {
    final label = _isToday
        ? 'Today'
        : '${_selectedDate.day} ${_kMonths[_selectedDate.month - 1]} ${_selectedDate.year}';
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            onPressed: _prevDay,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _isToday ? null : () {
                setState(() { _selectedDate = DateTime.now(); _loading = true; });
                _load();
              },
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isToday ? const Color(0xFFFFD700) : const Color(0xFFCCCCDD),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  )),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded,
                color: _isToday ? const Color(0xFF333355) : Colors.white),
            onPressed: _isToday ? null : _nextDay,
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSummary() {
    final calLeft = (_goals.calories - _totals.calories).clamp(0, double.infinity);
    final calOver = _totals.calories > _goals.calories;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_totals.calories.round().toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, height: 1)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('/ ${_goals.calories.round()} kcal',
                    style: const TextStyle(color: Color(0xFF555577), fontSize: 14)),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(calOver ? 'Over by' : 'Remaining',
                      style: const TextStyle(color: Color(0xFF555577), fontSize: 11)),
                  Text(
                    '${calOver ? (_totals.calories - _goals.calories).round() : calLeft.round()} kcal',
                    style: TextStyle(
                      color: calOver ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_totals.calories / _goals.calories).clamp(0, 1),
              minHeight: 6,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: AlwaysStoppedAnimation(
                  calOver ? const Color(0xFFE74C3C) : const Color(0xFFFFD700)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _macroBar('Protein', _totals.proteinG, _goals.proteinG, const Color(0xFF3498DB)),
              const SizedBox(width: 10),
              _macroBar('Carbs', _totals.carbsG, _goals.carbsG, const Color(0xFF2ECC71)),
              const SizedBox(width: 10),
              _macroBar('Fat', _totals.fatG, _goals.fatG, const Color(0xFFE67E22)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroBar(String label, double current, double goal, Color color) {
    final pct = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF888899), fontSize: 11)),
              Text('${current.round()}g',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 2),
          Text('/ ${goal.round()}g',
              style: const TextStyle(color: Color(0xFF444466), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMealSection(String mealKey) {
    final name = _displayName(mealKey);
    final entries = _totals.entries.where((e) => e.mealType == mealKey).toList();
    final mealCal = entries.fold(0.0, (s, e) => s + e.calories);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        children: [
          // Header — tap to add, long-press to rename
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => _showAddFood(mealKey: mealKey),
            onLongPress: () => _renameMeal(mealKey),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Text(_iconForKey(mealKey), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (mealCal > 0)
                    Text('${mealCal.round()} kcal',
                        style: const TextStyle(color: Color(0xFF888899), fontSize: 13)),
                  // ⋮ options menu (rename / save preset / delete meal)
                  PopupMenuButton<_MealAction>(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Color(0xFF555577), size: 18),
                    color: const Color(0xFF1E1E35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (action) {
                      switch (action) {
                        case _MealAction.rename:
                          _renameMeal(mealKey);
                        case _MealAction.copyFromYesterday:
                          _copyMealFromYesterday(mealKey, name);
                        case _MealAction.savePreset:
                          _saveAsPreset(mealKey);
                        case _MealAction.deleteAll:
                          _deleteMeal(mealKey, name);
                        case _MealAction.deleteMeal:
                          _deleteMealSlot(mealKey, name);
                      }
                    },
                    itemBuilder: (_) => [
                      _mealMenuItem(_MealAction.rename,
                          Icons.edit_rounded, 'Rename meal'),
                      _mealMenuItem(_MealAction.copyFromYesterday,
                          Icons.content_copy_rounded, 'Copy from yesterday'),
                      if (entries.isNotEmpty)
                        _mealMenuItem(_MealAction.savePreset,
                            Icons.bookmark_add_outlined, 'Save as preset'),
                      _mealMenuItem(_MealAction.deleteAll,
                          Icons.delete_sweep_rounded, 'Delete all items',
                          color: entries.isNotEmpty
                              ? const Color(0xFFE74C3C)
                              : const Color(0xFF444466)),
                      _mealMenuItem(_MealAction.deleteMeal,
                          Icons.delete_forever_rounded, 'Delete meal',
                          color: const Color(0xFFE74C3C)),
                    ],
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.add_circle_outline_rounded,
                      color: Color(0xFFFFD700), size: 20),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (entries.isNotEmpty) const Divider(height: 1, color: Color(0xFF1E1E35)),
          ...entries.map((e) => _buildEntryRow(e)),
        ],
      ),
    );
  }

  Widget _buildEntryRow(NutritionEntry e) {
    final totalGrams = e.quantity * e.food.servingSize;
    final String servingLabel;
    final unit = e.food.servingUnit;
    if (unit == 'g' || unit == 'ml') {
      final gramsStr = totalGrams % 1 == 0
          ? totalGrams.toInt().toString()
          : totalGrams.toStringAsFixed(1);
      servingLabel = '$gramsStr$unit';
    } else {
      // Supplement/custom units like "scoop (33g)", "tablet (1.82g)", etc.
      final qtyStr = e.quantity == e.quantity.truncateToDouble()
          ? e.quantity.toInt().toString()
          : e.quantity.toStringAsFixed(2);
      servingLabel = '$qtyStr × $unit';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.food.name,
                        style: const TextStyle(
                            color: Color(0xFFCCCCDD),
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(servingLabel,
                        style: const TextStyle(color: Color(0xFF555577), fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${e.calories.round()} kcal',
                      style: const TextStyle(
                          color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('P ${e.proteinG.toStringAsFixed(1)}g',
                      style: const TextStyle(color: Color(0xFF3498DB), fontSize: 11)),
                ],
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_EntryAction>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: Color(0xFF555577), size: 18),
                color: const Color(0xFF1E1E35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (action) {
                  switch (action) {
                    case _EntryAction.edit:
                      _editEntry(e);
                    case _EntryAction.move:
                      _moveEntry(e);
                    case _EntryAction.delete:
                      _deleteEntry(e);
                  }
                },
                itemBuilder: (_) => [
                  _menuItem(_EntryAction.edit, Icons.edit_rounded, 'Edit quantity'),
                  _menuItem(_EntryAction.move, Icons.swap_horiz_rounded, 'Move to meal'),
                  _menuItem(_EntryAction.delete, Icons.delete_outline_rounded, 'Delete',
                      color: const Color(0xFFE74C3C)),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF1E1E35), indent: 16),
      ],
    );
  }

  PopupMenuItem<_EntryAction> _menuItem(_EntryAction action, IconData icon, String label,
      {Color color = const Color(0xFFCCCCDD)}) {
    return PopupMenuItem(
      value: action,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  PopupMenuItem<_MealAction> _mealMenuItem(_MealAction action, IconData icon, String label,
      {Color color = const Color(0xFFCCCCDD)}) {
    return PopupMenuItem(
      value: action,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _openPresets() async {
    final logged = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MealPresetsScreen(logToDate: _dateStr)),
    );
    if (logged == true) _load();
  }

  Future<void> _saveAsPreset(String mealKey) async {
    final entries =
        _totals.entries.where((e) => e.mealType == mealKey).toList();
    if (entries.isEmpty) return;

    final ctrl = TextEditingController(text: _displayName(mealKey));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save as Preset',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Preset name',
            hintStyle: const TextStyle(color: Color(0xFF444466)),
            filled: true,
            fillColor: const Color(0xFF0D0D1A),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFFD700))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => popAfterFocusSettles(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              popAfterFocusSettles(ctx, v.isNotEmpty ? v : null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    await _db.createMealPreset(name, entries);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"$name" saved to presets'),
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'View',
        textColor: const Color(0xFFFFD700),
        onPressed: _openPresets,
      ),
    ));
  }

  Future<void> _openGoals() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NutritionGoalsScreen()),
    );
    if (saved == true) _load();
  }

  static const _kMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

enum _EntryAction { edit, move, delete }

enum _MealAction { rename, savePreset, deleteAll, deleteMeal, copyFromYesterday }
