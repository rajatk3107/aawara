import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../screens/add_custom_food_screen.dart';
import '../screens/barcode_scanner_screen.dart';

Future<bool> showAddFoodSheet(
  BuildContext context, {
  required String date,
  required String meal,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddFoodSheet(date: date, meal: meal),
  );
  return result == true;
}

class AddFoodSheet extends StatefulWidget {
  final String date;
  final String meal;

  const AddFoodSheet({super.key, required this.date, required this.meal});

  @override
  State<AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<AddFoodSheet> {
  final _db = WorkoutDatabase.instance;
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  List<Food> _results = [];
  bool _searching = false;
  Food? _selected;
  double _quantity = 1.0;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
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
    if (mounted) Navigator.pop(context, true);
  }

  void _adjustQty(double delta) {
    final next = (_quantity + delta).clamp(0.25, 99.0);
    final rounded = (next * 4).round() / 4;
    setState(() {
      _quantity = rounded;
      _qtyCtrl.text = _fmtQty(rounded);
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
                        : 'Add to ${widget.meal}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: Color(0xFF555577)),
                ),
              ],
            ),
          ),

          if (_selected == null) ...[
            const SizedBox(height: 12),
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
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
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
          ] else
            const SizedBox(height: 8),

          Expanded(
            child: _selected != null
                ? _buildQuantityPicker()
                : _searching
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFFFFD700), strokeWidth: 2))
                    : _results.isEmpty
                        ? const Center(
                            child: Text('No foods found',
                                style: TextStyle(color: Color(0xFF555577))))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _buildFoodTile(_results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodTile(Food food) {
    return InkWell(
      onTap: () => setState(() {
        _selected = food;
        _quantity = 1.0;
        _qtyCtrl.text = '1';
      }),
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
    final servingAmt = (f.servingSize * _quantity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('per ${f.servingSize.round()}${f.servingUnit}',
              style: const TextStyle(color: Color(0xFF555577), fontSize: 13)),
          const SizedBox(height: 20),

          // Quantity row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Text('Servings',
                    style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepBtn(Icons.remove_rounded,
                        () => _adjustQty(-0.25)),
                    const SizedBox(width: 28),
                    Column(
                      children: [
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: _qtyCtrl,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+\.?\d{0,2}'))
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
                        Text(
                          '${servingAmt % 1 == 0 ? servingAmt.toInt() : servingAmt.toStringAsFixed(1)}${f.servingUnit}',
                          style: const TextStyle(
                              color: Color(0xFF555577), fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(width: 28),
                    _stepBtn(Icons.add_rounded, () => _adjustQty(0.25)),
                  ],
                ),
              ],
            ),
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
                  : Text('Add to ${widget.meal}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
    if (added == true && mounted) Navigator.pop(context, true);
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
