import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../../utils/safe_navigation.dart';

Future<bool?> showEditFoodEntrySheet(
  BuildContext context, {
  required NutritionEntry entry,
  required Map<String, String> mealNames,
  required Map<String, String> defaultMealNames,
  required List<String> mealKeys,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EditFoodEntrySheet(
      entry: entry,
      mealNames: mealNames,
      defaultMealNames: defaultMealNames,
      mealKeys: mealKeys,
    ),
  );
}

class EditFoodEntrySheet extends StatefulWidget {
  final NutritionEntry entry;
  final Map<String, String> mealNames;
  final Map<String, String> defaultMealNames;
  final List<String> mealKeys;

  const EditFoodEntrySheet({
    super.key,
    required this.entry,
    required this.mealNames,
    required this.defaultMealNames,
    required this.mealKeys,
  });

  @override
  State<EditFoodEntrySheet> createState() => _EditFoodEntrySheetState();
}

class _EditFoodEntrySheetState extends State<EditFoodEntrySheet> {
  final _db = WorkoutDatabase.instance;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _gramsCtrl;

  late double _quantity;
  late String _mealKey;
  bool _byGrams = false;
  bool _saving = false;

  Food get _food => widget.entry.food;

  @override
  void initState() {
    super.initState();
    _quantity = widget.entry.quantity;
    _mealKey = widget.entry.mealType;
    _qtyCtrl = TextEditingController(text: _fmtQty(_quantity));
    _gramsCtrl = TextEditingController(
        text: _fmtGrams(_quantity * _food.servingSize));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _gramsCtrl.dispose();
    super.dispose();
  }

  String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  String _fmtGrams(double g) =>
      g == g.truncateToDouble() ? g.toInt().toString() : g.toStringAsFixed(1);

  String _displayName(String key) =>
      widget.mealNames[key] ?? widget.defaultMealNames[key] ?? key;

  String _naturalUnit() {
    final n = _food.name.toLowerCase();
    if (n.contains('egg')) return 'egg';
    if (n.contains('idli')) return 'idli';
    if (n.contains('dosa')) return 'dosa';
    if (n.contains('roti') || n.contains('chapati')) return 'roti';
    if (n.contains('paratha')) return 'paratha';
    if (n.contains('puri')) return 'puri';
    if (_food.servingUnit == 'ml') return 'glass';
    if (_food.servingSize >= 80) return 'bowl';
    return 'serving';
  }

  double _countStep() {
    const wholeOnly = {'egg', 'idli', 'dosa', 'roti', 'paratha', 'puri'};
    return wholeOnly.contains(_naturalUnit()) ? 1.0 : 0.5;
  }

  double _gramStep() => _food.servingSize <= 50 ? 10 : 25;

  void _switchMode(bool toGrams) {
    setState(() {
      if (toGrams) {
        _gramsCtrl.text = _fmtGrams(_quantity * _food.servingSize);
      } else {
        final g = double.tryParse(_gramsCtrl.text) ?? _food.servingSize;
        _quantity = (g / _food.servingSize * 4).round() / 4;
        _qtyCtrl.text = _fmtQty(_quantity);
      }
      _byGrams = toGrams;
    });
  }

  void _adjustQty(double delta) {
    final next = ((_quantity + delta) * 4).round() / 4;
    final clamped = next.clamp(0.25, 99.0);
    setState(() {
      _quantity = clamped;
      _qtyCtrl.text = _fmtQty(clamped);
    });
  }

  void _adjustGrams(double delta) {
    final cur = double.tryParse(_gramsCtrl.text) ?? _food.servingSize;
    final next = (cur + delta).clamp(1.0, 9999.0);
    setState(() {
      _gramsCtrl.text = _fmtGrams(next);
      _quantity = next / _food.servingSize;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _db.updateNutritionEntry(widget.entry.id,
        quantity: _quantity, mealType: _mealKey);
    if (mounted) popAfterFocusSettles(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final cal = (_food.calories * _quantity).round();
    final prot = _food.proteinG * _quantity;
    final carbs = _food.carbsG * _quantity;
    final fat = _food.fatG * _quantity;
    final totalGrams = _quantity * _food.servingSize;
    final unit = _naturalUnit();
    final unitLabel = _quantity == 1.0 ? unit : '${unit}s';
    final countStep = _countStep();
    final gramStep = _gramStep();

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
                borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _food.name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => popAfterFocusSettles(context),
                  child: const Icon(Icons.close_rounded, color: Color(0xFF555577)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Serving reference
                  Text(
                    'per ${_food.servingSize.round()}${_food.servingUnit} · 1 $unit',
                    style: const TextStyle(color: Color(0xFF555577), fontSize: 13),
                  ),
                  const SizedBox(height: 14),

                  // Mode toggle
                  Container(
                    decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(10)),
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
                        borderRadius: BorderRadius.circular(14)),
                    child: _byGrams
                        ? _buildGramInput(gramStep, totalGrams)
                        : _buildCountInput(countStep, totalGrams, unitLabel),
                  ),
                  const SizedBox(height: 12),

                  // Macro preview
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _macroChip('Calories', '$cal', const Color(0xFFFFD700)),
                        _macroChip('Protein', '${prot.toStringAsFixed(1)}g', const Color(0xFF3498DB)),
                        _macroChip('Carbs', '${carbs.toStringAsFixed(1)}g', const Color(0xFF2ECC71)),
                        _macroChip('Fat', '${fat.toStringAsFixed(1)}g', const Color(0xFFE67E22)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Meal selector
                  _buildMealSelector(),

                  const Spacer(),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Meal',
            style: TextStyle(color: Color(0xFF888899), fontSize: 12, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.mealKeys.map((key) {
              final selected = key == _mealKey;
              return GestureDetector(
                onTap: () => setState(() => _mealKey = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                        : const Color(0xFF0D0D1A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                          : const Color(0xFF333355),
                    ),
                  ),
                  child: Text(
                    _displayName(key),
                    style: TextStyle(
                      color: selected ? const Color(0xFFFFD700) : const Color(0xFF888899),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCountInput(double step, double totalGrams, String unitLabel) {
    final gramsStr = totalGrams % 1 == 0
        ? totalGrams.toInt().toString()
        : totalGrams.toStringAsFixed(1);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepBtn(Icons.remove_rounded, _quantity > step ? () => _adjustQty(-step) : null),
        const SizedBox(width: 24),
        Column(
          children: [
            SizedBox(
              width: 80,
              child: TextField(
                controller: _qtyCtrl,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                decoration: const InputDecoration(
                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed != null && parsed > 0) setState(() => _quantity = parsed);
                },
              ),
            ),
            Text(unitLabel, style: const TextStyle(color: Color(0xFF555577), fontSize: 13)),
            const SizedBox(height: 4),
            Text('= $gramsStr${_food.servingUnit}',
                style: const TextStyle(color: Color(0xFF444466), fontSize: 11)),
          ],
        ),
        const SizedBox(width: 24),
        _stepBtn(Icons.add_rounded, () => _adjustQty(step)),
      ],
    );
  }

  Widget _buildGramInput(double step, double totalGrams) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepBtn(Icons.remove_rounded, totalGrams > step ? () => _adjustGrams(-step) : null),
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
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
                    ],
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    onChanged: (v) {
                      final g = double.tryParse(v);
                      if (g != null && g > 0) setState(() => _quantity = g / _food.servingSize);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(_food.servingUnit,
                      style: const TextStyle(color: Color(0xFF555577), fontSize: 16)),
                ),
              ],
            ),
            Text('= ${_fmtQty(_quantity)} ${_naturalUnit()}${_quantity != 1 ? 's' : ''}',
                style: const TextStyle(color: Color(0xFF444466), fontSize: 11)),
          ],
        ),
        const SizedBox(width: 24),
        _stepBtn(Icons.add_rounded, () => _adjustGrams(step)),
      ],
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
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF555577),
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(11)),
        child: Icon(icon,
            color: onTap == null ? const Color(0xFF333355) : Colors.white, size: 22),
      ),
    );
  }

  Widget _macroChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFF555577), fontSize: 11)),
      ],
    );
  }
}
