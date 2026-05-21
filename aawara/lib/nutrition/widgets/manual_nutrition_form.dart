import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

/// Inline form shown when a barcode isn't found on Open Food Facts.
/// Lets the user manually enter nutrition data and log it immediately.
class ManualNutritionForm extends StatefulWidget {
  final String barcode;
  final String date;
  final String meal;
  final VoidCallback onAdded;
  final VoidCallback onRescan;

  const ManualNutritionForm({
    super.key,
    required this.barcode,
    required this.date,
    required this.meal,
    required this.onAdded,
    required this.onRescan,
  });

  @override
  State<ManualNutritionForm> createState() => _ManualNutritionFormState();
}

class _ManualNutritionFormState extends State<ManualNutritionForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  bool _saving = false;

  double get _cal => double.tryParse(_calCtrl.text) ?? 0;
  double get _prot => double.tryParse(_protCtrl.text) ?? 0;
  double get _carbs => double.tryParse(_carbsCtrl.text) ?? 0;
  double get _fat => double.tryParse(_fatCtrl.text) ?? 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _calCtrl.dispose();
    _protCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final db = WorkoutDatabase.instance;
    final food = Food(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
      calories: _cal,
      proteinG: _prot,
      carbsG: _carbs,
      fatG: _fat,
      servingSize: 100,
      servingUnit: 'g',
      isCustom: true,
      barcode: widget.barcode,
      source: 'manual',
      lastUpdated: DateTime.now().toIso8601String(),
    );
    final saved = await db.upsertFoodFromApi(food);
    // Mark barcode as found in scan cache so future scans resolve locally
    final existing = await db.getScanCache(widget.barcode);
    await db.upsertScanCache(ScanCacheEntry(
      barcode: widget.barcode,
      foodId: saved.id,
      status: 'found',
      scanCount: (existing?.scanCount ?? 0) + 1,
      lastScannedAt: DateTime.now().toIso8601String(),
    ));
    await db.addNutritionEntry(widget.date, saved.id, widget.meal, 1.0);
    if (mounted) widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Form(
        key: _formKey,
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Product name *', _nameCtrl,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
            const SizedBox(height: 10),
            _field('Brand (optional)', _brandCtrl),
            const SizedBox(height: 16),
            const Text('Nutrition per 100g',
                style: TextStyle(color: Color(0xFF888899), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numField('Calories *', _calCtrl, const Color(0xFFFFD700))),
                const SizedBox(width: 8),
                Expanded(child: _numField('Protein (g) *', _protCtrl, const Color(0xFF5DCAA5))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numField('Carbs (g) *', _carbsCtrl, const Color(0xFFEF9F27))),
                const SizedBox(width: 8),
                Expanded(child: _numField('Fat (g) *', _fatCtrl, const Color(0xFFF0997B))),
              ],
            ),
            const SizedBox(height: 14),
            // Live preview
            if (_cal > 0 || _prot > 0 || _carbs > 0 || _fat > 0)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Container(
                  key: const ValueKey('preview'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D1A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _previewMacro('Calories', _cal.round().toString(),
                          const Color(0xFFFFD700)),
                      _previewMacro('Protein', '${_prot.toStringAsFixed(1)}g',
                          const Color(0xFF5DCAA5)),
                      _previewMacro('Carbs', '${_carbs.toStringAsFixed(1)}g',
                          const Color(0xFFEF9F27)),
                      _previewMacro('Fat', '${_fat.toStringAsFixed(1)}g',
                          const Color(0xFFF0997B)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onRescan,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF888899),
                      side: const BorderSide(color: Color(0xFF333355)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Rescan'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
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
                        : const Text('Save & Log',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String hint, TextEditingController ctrl,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555577), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Color(0xFFE74C3C), fontSize: 11),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _numField(String hint, TextEditingController ctrl, Color color) {
    return TextFormField(
      controller: ctrl,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))
      ],
      validator: (v) {
        if (hint.contains('*')) {
          final d = double.tryParse(v ?? '');
          if (d == null || d < 0) return 'Must be ≥ 0';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: hint.replaceAll(' *', ''),
        hintStyle: const TextStyle(color: Color(0xFF555577), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Color(0xFFE74C3C), fontSize: 10),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _previewMacro(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(color: Color(0xFF555577), fontSize: 10)),
        ],
      );
}
