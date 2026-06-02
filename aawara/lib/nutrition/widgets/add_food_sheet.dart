import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../../utils/safe_navigation.dart';
import '../screens/add_custom_food_screen.dart';
import '../screens/barcode_scanner_screen.dart';

Future<bool> showAddFoodSheet(
  BuildContext context, {
  required String date,
  required String meal,
  String? mealDisplayName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddFoodSheet(date: date, meal: meal, mealDisplayName: mealDisplayName),
  );
  return result == true;
}

class AddFoodSheet extends StatefulWidget {
  final String date;
  final String meal;
  final String? mealDisplayName;

  const AddFoodSheet({super.key, required this.date, required this.meal, this.mealDisplayName});

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  final _db = WorkoutDatabase.instance;
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _gramsCtrl = TextEditingController();

  List<Food> _results = [];
  bool _searching = false;
  Food? _selected;
  double _quantity = 1.0; // always in servings internally
  bool _adding = false;
  bool _byGrams = false; // false = count/serving mode, true = gram mode
  int _tab = 0; // 0 = Search, 1 = Presets
  List<MealPreset> _presets = [];
  bool _loadingPresets = false;

  @override
  void initState() {
    super.initState();
    _search('');
    _loadPresets();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _gramsCtrl.dispose();
    super.dispose();
  }

  // Returns smart natural-unit label for a food (singular).
  String _naturalUnit(Food food) {
    final n = food.name.toLowerCase();
    if (n.contains('egg')) return 'egg';
    if (n.contains('idli')) return 'idli';
    if (n.contains('dosa')) return 'dosa';
    if (n.contains('uttapam')) return 'piece';
    if (n.contains('roti') || n.contains('chapati')) return 'roti';
    if (n.contains('paratha')) return 'paratha';
    if (n.contains('puri')) return 'puri';
    if (n.contains('naan') || n.contains('kulcha') || n.contains('bhatura')) return 'piece';
    if (n.contains('samosa')) return 'samosa';
    if (n.contains('vada') || n.contains('wada')) return 'vada';
    if (n.contains('dhokla') || n.contains('thepla')) return 'piece';
    if (n.contains('gulab jamun') || n.contains('rasgulla')) return 'piece';
    if (n.contains('laddoo') || n.contains('barfi') || n.contains('kaju')) return 'piece';
    if (food.servingUnit == 'ml') return 'glass';
    if (food.servingSize >= 150) return 'bowl';
    if (food.servingSize >= 80) return 'bowl';
    return 'serving';
  }

  String _pluralUnit(Food food) {
    final u = _naturalUnit(food);
    const noChange = {'serving'};
    if (noChange.contains(u)) return '${u}s';
    return '${u}s';
  }

  // Natural-unit step: whole pieces for countable items, 0.5 for bowls/glasses
  double _countStep(Food food) {
    final u = _naturalUnit(food);
    const wholeOnly = {'egg', 'idli', 'dosa', 'roti', 'paratha', 'puri',
        'samosa', 'vada', 'piece', 'uttapam', 'naan'};
    return wholeOnly.contains(u) ? 1.0 : 0.5;
  }

  // Gram step: 10g for small foods, 25g for larger
  double _gramStep(Food food) => food.servingSize <= 50 ? 10 : 25;

  Future<void> _loadPresets() async {
    setState(() => _loadingPresets = true);
    final p = await _db.getMealPresets();
    if (mounted) setState(() { _presets = p; _loadingPresets = false; });
  }

  Future<void> _logPreset(MealPreset preset) async {
    await _db.logMealPreset(preset.id, widget.date, widget.meal);
    if (mounted) popAfterFocusSettles(context, true);
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    final results = await _db.searchFoods(q);
    if (mounted) setState(() { _results = results; _searching = false; });
  }

  Future<void> _addEntry() async {
    if (_selected == null) return;
    setState(() => _adding = true);
    await _db.addNutritionEntry(
        widget.date, _selected!.id, widget.meal, _quantity);
    if (mounted) popAfterFocusSettles(context, true);
  }

  void _selectFood(Food food) {
    setState(() {
      _selected = food;
      _quantity = 1.0;
      _byGrams = false;
      _qtyCtrl.text = '1';
      _gramsCtrl.text = food.servingSize.round().toString();
    });
  }

  void _switchMode(bool toGrams) {
    if (_selected == null) return;
    setState(() {
      if (toGrams) {
        // Convert current serving count → grams
        final g = (_quantity * _selected!.servingSize).roundToDouble();
        _gramsCtrl.text = g.round().toString();
      } else {
        // Convert current grams → serving count
        final g = double.tryParse(_gramsCtrl.text) ?? _selected!.servingSize;
        final q = (g / _selected!.servingSize);
        _quantity = (q * 4).round() / 4; // round to nearest 0.25
        _qtyCtrl.text = _fmtQty(_quantity);
      }
      _byGrams = toGrams;
    });
  }

  void _adjustQty(double delta) {
    final next = (_quantity + delta).clamp(0.25, 99.0);
    final rounded = (next * 4).round() / 4;
    setState(() {
      _quantity = rounded;
      _qtyCtrl.text = _fmtQty(rounded);
    });
  }

  void _adjustGrams(double delta) {
    if (_selected == null) return;
    final cur = double.tryParse(_gramsCtrl.text) ?? _selected!.servingSize;
    final next = (cur + delta).clamp(1.0, 9999.0);
    final rounded = next.roundToDouble();
    setState(() {
      _gramsCtrl.text = rounded == rounded.truncateToDouble()
          ? rounded.toInt().toString()
          : rounded.toStringAsFixed(1);
      _quantity = rounded / _selected!.servingSize;
    });
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    return Container(
      height: screenH * 0.88,
      padding: EdgeInsets.only(bottom: kb),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF333355),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                if (_selected != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selected = null;
                      _quantity = 1.0;
                      _byGrams = false;
                      _qtyCtrl.text = '1';
                    }),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: Color(0xFF888899)),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _selected != null
                        ? _selected!.name
                        : 'Add to ${widget.mealDisplayName ?? widget.meal}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => popAfterFocusSettles(context),
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF555577)),
                ),
              ],
            ),
          ),

          if (_selected == null) ...[
            const SizedBox(height: 12),
            // Tab switcher: Search | Presets
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTabSwitcher(),
            ),
            if (_tab == 0) ...[
              const SizedBox(height: 10),
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search foods…',
                    hintStyle: const TextStyle(color: Color(0xFF444466)),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF555577)),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchCtrl.clear();
                              _search('');
                            },
                            child: const Icon(Icons.close_rounded,
                                color: Color(0xFF444466), size: 18),
                          )
                        : null,
                  ),
                  onChanged: _search,
                ),
              ),
              // Quick-action row: create custom + scan barcode
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _openCustomFood,
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 16),
                      label: const Text('Create custom'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD700),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _openBarcodeScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: const Text('Scan barcode'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF3498DB),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1E1E35)),
            ],
          ] else
            const SizedBox(height: 8),

          Expanded(
            child: _selected != null
                ? _buildQuantityPicker()
                : _tab == 1
                    ? _buildPresetsList()
                    : _searching
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFFD700), strokeWidth: 2))
                        : _results.isEmpty
                            ? const Center(
                                child: Text('No foods found',
                                    style:
                                        TextStyle(color: Color(0xFF555577))))
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (_, i) =>
                                    _buildFoodTile(_results[i]),
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tabChip('Search', 0, Icons.search_rounded),
          _tabChip('Presets', 1, Icons.bookmark_rounded),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int idx, IconData icon) {
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A1A2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF555577)),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF555577),
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetsList() {
    if (_loadingPresets) {
      return const Center(
        child: CircularProgressIndicator(
            color: Color(0xFFFFD700), strokeWidth: 2),
      );
    }
    if (_presets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_outline_rounded,
                color: Color(0xFF333355), size: 42),
            SizedBox(height: 12),
            Text('No saved presets',
                style:
                    TextStyle(color: Color(0xFF888899), fontSize: 14)),
            SizedBox(height: 6),
            Text(
              'Log a meal, then tap the bookmark\nicon to save it as a preset.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Color(0xFF444466), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: _presets.length,
      itemBuilder: (_, i) => _buildPresetRow(_presets[i]),
    );
  }

  Widget _buildPresetRow(MealPreset preset) {
    return Dismissible(
      key: Key(preset.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFFE74C3C).withValues(alpha: 0.12),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFE74C3C), size: 20),
      ),
      confirmDismiss: (_) async {
        await _db.deleteMealPreset(preset.id);
        _loadPresets();
        return false;
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.name,
                      style: const TextStyle(
                          color: Color(0xFFCCCCDD),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    '${preset.items.length} items · '
                    '${preset.totalCalories.round()} kcal · '
                    'P ${preset.totalProtein.toStringAsFixed(0)}g',
                    style: const TextStyle(
                        color: Color(0xFF555577), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _logPreset(preset),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Log',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodTile(Food food) {
    return InkWell(
      onTap: () => _selectFood(food),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(food.name,
                      style: const TextStyle(
                          color: Color(0xFFCCCCDD),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                      '${food.servingSize.round()}${food.servingUnit} · '
                      '${food.calories.round()} kcal',
                      style: const TextStyle(
                          color: Color(0xFF555577), fontSize: 12)),
                ],
              ),
            ),
            Text('P ${food.proteinG.toStringAsFixed(1)}g',
                style:
                    const TextStyle(color: Color(0xFF3498DB), fontSize: 12)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF333355), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityPicker() {
    final f = _selected!;
    final cal = (f.calories * _quantity).round();
    final prot = f.proteinG * _quantity;
    final carbs = f.carbsG * _quantity;
    final fat = f.fatG * _quantity;
    final totalGrams = _quantity * f.servingSize;
    final unit = _naturalUnit(f);
    final unitLabel = _quantity == 1.0 ? unit : _pluralUnit(f);
    final gramStep = _gramStep(f);
    final countStep = _countStep(f);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serving reference
          Text(
            'per ${f.servingSize.round()}${f.servingUnit} · 1 $unit',
            style: const TextStyle(color: Color(0xFF555577), fontSize: 13),
          ),
          const SizedBox(height: 14),

          // Mode toggle
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _modeTab('By count', !_byGrams, () => _switchMode(false)),
                _modeTab('By grams', _byGrams, () => _switchMode(true)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quantity input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _byGrams
                ? _buildGramInput(f, gramStep, totalGrams)
                : _buildCountInput(f, countStep, totalGrams, unitLabel),
          ),
          const SizedBox(height: 14),

          // Macro preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _macroChip('Calories', '$cal', const Color(0xFFFFD700)),
                _macroChip('Protein', '${prot.toStringAsFixed(1)}g',
                    const Color(0xFF3498DB)),
                _macroChip('Carbs', '${carbs.toStringAsFixed(1)}g',
                    const Color(0xFF2ECC71)),
                _macroChip('Fat', '${fat.toStringAsFixed(1)}g',
                    const Color(0xFFE67E22)),
              ],
            ),
          ),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _adding ? null : _addEntry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text('Add to ${widget.mealDisplayName ?? widget.meal}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A1A2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF555577),
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountInput(
      Food f, double step, double totalGrams, String unitLabel) {
    final gramsStr = totalGrams % 1 == 0
        ? totalGrams.toInt().toString()
        : totalGrams.toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepBtn(Icons.remove_rounded,
            _quantity > step ? () => _adjustQty(-step) : null),
        const SizedBox(width: 24),
        Column(
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _qtyCtrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                ],
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed > 0) {
                    setState(() => _quantity = parsed);
                  }
                },
              ),
            ),
            Text(unitLabel,
                style: const TextStyle(
                    color: Color(0xFF555577), fontSize: 13)),
            const SizedBox(height: 4),
            Text('= $gramsStr${f.servingUnit}',
                style: const TextStyle(
                    color: Color(0xFF444466), fontSize: 11)),
          ],
        ),
        const SizedBox(width: 24),
        _stepBtn(Icons.add_rounded, () => _adjustQty(step)),
      ],
    );
  }

  Widget _buildGramInput(Food f, double step, double totalGrams) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepBtn(Icons.remove_rounded,
            totalGrams > step ? () => _adjustGrams(-step) : null),
        const SizedBox(width: 24),
        Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _gramsCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero),
                    onChanged: (v) {
                      final g = double.tryParse(v);
                      if (g != null && g > 0) {
                        setState(() => _quantity = g / f.servingSize);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(f.servingUnit,
                      style: const TextStyle(
                          color: Color(0xFF555577), fontSize: 16)),
                ),
              ],
            ),
            Text(
              '= ${_fmtQty(_quantity)} ${_naturalUnit(f)}${_quantity != 1 ? 's' : ''}',
              style: const TextStyle(
                  color: Color(0xFF444466), fontSize: 11),
            ),
          ],
        ),
        const SizedBox(width: 24),
        _stepBtn(Icons.add_rounded, () => _adjustGrams(step)),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon,
            color: onTap == null
                ? const Color(0xFF333355)
                : Colors.white,
            size: 22),
      ),
    );
  }

  Widget _macroChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF555577), fontSize: 11)),
      ],
    );
  }

  Future<void> _openBarcodeScanner() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(
          date: widget.date,
          meal: widget.meal,
        ),
      ),
    );
    // Scanner already added the entry to the log — close this sheet too.
    if (added == true && mounted) popAfterFocusSettles(context, true);
  }

  Future<void> _openCustomFood() async {
    final created = await Navigator.push<Food>(
      context,
      MaterialPageRoute(
          builder: (_) => AddCustomFoodScreen(date: widget.date, meal: widget.meal)),
    );
    if (created != null && mounted) {
      // Select the newly created food
      setState(() {
        _selected = created;
        _quantity = 1.0;
        _qtyCtrl.text = '1';
      });
    }
  }
}
