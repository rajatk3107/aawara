import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

class AddCustomFoodScreen extends StatefulWidget {
  final String? date;
  final String? meal;

  const AddCustomFoodScreen({super.key, this.date, this.meal});

  @override
  State<AddCustomFoodScreen> createState() => _AddCustomFoodScreenState();
}

class _AddCustomFoodScreenState extends State<AddCustomFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _fiberCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController(text: '100');
  String _unit = 'g';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _calCtrl, _protCtrl, _carbsCtrl, _fatCtrl, _fiberCtrl, _sizeCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final food = Food(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      calories: double.parse(_calCtrl.text),
      proteinG: double.parse(_protCtrl.text),
      carbsG: double.parse(_carbsCtrl.text),
      fatG: double.parse(_fatCtrl.text),
      fiberG: _fiberCtrl.text.isEmpty ? null : double.tryParse(_fiberCtrl.text),
      servingSize: double.parse(_sizeCtrl.text),
      servingUnit: _unit,
      isCustom: true,
    );

    final created = await WorkoutDatabase.instance.createCustomFood(food);
    if (mounted) Navigator.pop(context, created);
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
        title: const Text('Create Custom Food',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel('Food Name'),
            _field(_nameCtrl, 'e.g. Homemade Dal Tadka',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null),
            const SizedBox(height: 20),

            _sectionLabel('Serving Size'),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field(_sizeCtrl, '100',
                      numeric: true,
                      validator: (v) {
                        final n = double.tryParse(v ?? '');
                        if (n == null || n <= 0) return 'Invalid size';
                        return null;
                      }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E1E35)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _unit,
                        dropdownColor: const Color(0xFF1A1A2E),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        items: ['g', 'ml', 'oz', 'piece']
                            .map((u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? 'g'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel('Macros per serving'),
            _macroRow('Calories (kcal)', _calCtrl, required: true),
            const SizedBox(height: 12),
            _macroRow('Protein (g)', _protCtrl, required: true),
            const SizedBox(height: 12),
            _macroRow('Carbohydrates (g)', _carbsCtrl, required: true),
            const SizedBox(height: 12),
            _macroRow('Fat (g)', _fatCtrl, required: true),
            const SizedBox(height: 12),
            _macroRow('Fiber (g)', _fiberCtrl, required: false),
            const SizedBox(height: 32),

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
                    : const Text('Save Food',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Color(0xFF888899),
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    bool numeric = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
          : null,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF444466)),
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E1E35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E1E35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE74C3C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE74C3C)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _macroRow(String label, TextEditingController ctrl,
      {required bool required}) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Text(label,
              style: const TextStyle(color: Color(0xFFCCCCDD), fontSize: 14)),
        ),
        Expanded(
          child: _field(
            ctrl,
            required ? '0' : 'optional',
            numeric: true,
            validator: required
                ? (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (double.tryParse(v) == null) return 'Invalid';
                    return null;
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
