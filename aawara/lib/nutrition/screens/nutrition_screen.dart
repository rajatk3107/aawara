import 'package:flutter/material.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../widgets/add_food_sheet.dart';
import '../widgets/water_tracker_card.dart';
import 'meal_presets_screen.dart';
import 'nutrition_goals_screen.dart';

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
  bool _loading = true;

  static const _meals = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];

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
    ]);
    if (!mounted) return;
    setState(() {
      _totals = results[0] as NutritionTotals;
      _goals = (results[1] as NutritionGoals?) ?? NutritionGoals.defaults;
      _loading = false;
    });
  }

  void _prevDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _loading = true;
    });
    _load();
  }

  void _nextDay() {
    if (_isToday) return;
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _loading = true;
    });
    _load();
  }

  Future<void> _deleteEntry(String entryId) async {
    await _db.deleteNutritionEntry(entryId);
    _load();
  }

  Future<void> _showAddFood({String meal = 'Snack'}) async {
    final added = await showAddFoodSheet(context, date: _dateStr, meal: meal);
    if (added) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: const Color(0xFF0D0D1A),
            foregroundColor: Colors.white,
            floating: true,
            snap: true,
            elevation: 0,
            title: const Text(
              'Nutrition',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_outline_rounded,
                    color: Color(0xFF888899)),
                tooltip: 'Saved Meals',
                onPressed: _openPresets,
              ),
              IconButton(
                icon: const Icon(Icons.track_changes_rounded,
                    color: Color(0xFF888899)),
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
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFFD700)))
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
                    ..._meals.map(_buildMealSection),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFood(),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Food',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
              onTap: _isToday
                  ? null
                  : () {
                      setState(() {
                        _selectedDate = DateTime.now();
                        _loading = true;
                      });
                      _load();
                    },
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isToday
                      ? const Color(0xFFFFD700)
                      : const Color(0xFFCCCCDD),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right_rounded,
              color: _isToday
                  ? const Color(0xFF333355)
                  : Colors.white,
            ),
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
          // Calorie row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _totals.calories.round().toString(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    height: 1),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ ${_goals.calories.round()} kcal',
                  style: const TextStyle(
                      color: Color(0xFF555577), fontSize: 14),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    calOver ? 'Over by' : 'Remaining',
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 11),
                  ),
                  Text(
                    '${calOver ? (_totals.calories - _goals.calories).round() : calLeft.round()} kcal',
                    style: TextStyle(
                      color: calOver
                          ? const Color(0xFFE74C3C)
                          : const Color(0xFF2ECC71),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Calorie progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_totals.calories / _goals.calories).clamp(0, 1),
              minHeight: 6,
              backgroundColor: const Color(0xFF0D0D1A),
              valueColor: AlwaysStoppedAnimation(
                calOver
                    ? const Color(0xFFE74C3C)
                    : const Color(0xFFFFD700),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Macro bars
          Row(
            children: [
              _macroBar('Protein', _totals.proteinG, _goals.proteinG,
                  const Color(0xFF3498DB)),
              const SizedBox(width: 10),
              _macroBar('Carbs', _totals.carbsG, _goals.carbsG,
                  const Color(0xFF2ECC71)),
              const SizedBox(width: 10),
              _macroBar('Fat', _totals.fatG, _goals.fatG,
                  const Color(0xFFE67E22)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroBar(
      String label, double current, double goal, Color color) {
    final pct = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 11)),
              Text('${current.round()}g',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
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
              style: const TextStyle(
                  color: Color(0xFF444466), fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMealSection(String meal) {
    final entries = _totals.entries
        .where((e) => e.mealType.toLowerCase() == meal.toLowerCase())
        .toList();
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
          // Header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: () => _showAddFoodForMeal(meal),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    _mealIcon(meal),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    meal,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (mealCal > 0) ...[
                    Text(
                      '${mealCal.round()} kcal',
                      style: const TextStyle(
                          color: Color(0xFF888899), fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _saveAsPreset(meal),
                      child: const Icon(Icons.bookmark_add_outlined,
                          color: Color(0xFF555577), size: 18),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Icon(Icons.add_circle_outline_rounded,
                      color: Color(0xFFFFD700), size: 20),
                ],
              ),
            ),
          ),
          // Entries
          if (entries.isNotEmpty)
            const Divider(height: 1, color: Color(0xFF1E1E35)),
          ...entries.map((e) => _buildEntryRow(e)),
        ],
      ),
    );
  }

  Widget _buildEntryRow(NutritionEntry e) {
    final servingLabel =
        '${(e.quantity * e.food.servingSize).round()}${e.food.servingUnit}';
    return Dismissible(
      key: Key(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: const BoxDecoration(
          color: Color(0xFFE74C3C),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 22),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                title: const Text('Remove entry?',
                    style: TextStyle(color: Colors.white)),
                content: Text(
                  'Remove ${e.food.name} from your log?',
                  style: const TextStyle(color: Color(0xFF888899)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel',
                        style: TextStyle(color: Color(0xFF888899))),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Remove',
                        style: TextStyle(color: Color(0xFFE74C3C))),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => _deleteEntry(e.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.food.name,
                    style: const TextStyle(
                        color: Color(0xFFCCCCDD),
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    servingLabel,
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${e.calories.round()} kcal',
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  'P ${e.proteinG.toStringAsFixed(1)}g',
                  style: const TextStyle(
                      color: Color(0xFF3498DB), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddFoodForMeal(String meal) => _showAddFood(meal: meal);

  Future<void> _openPresets() async {
    final logged = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => MealPresetsScreen(logToDate: _dateStr)),
    );
    if (logged == true) _load();
  }

  Future<void> _saveAsPreset(String meal) async {
    final entries = _totals.entries
        .where((e) => e.mealType.toLowerCase() == meal.toLowerCase())
        .toList();
    if (entries.isEmpty) return;

    final ctrl = TextEditingController(text: meal);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save as Preset',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
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
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFFFFD700))),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF888899)))),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isNotEmpty ? v : null);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
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

  String _mealIcon(String meal) {
    switch (meal) {
      case 'Breakfast':
        return '🌅';
      case 'Lunch':
        return '☀️';
      case 'Dinner':
        return '🌙';
      default:
        return '🍎';
    }
  }

  static const _kMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

