import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';
import '../../utils/safe_navigation.dart';

class NutritionGoalsScreen extends StatefulWidget {
  const NutritionGoalsScreen({super.key});

  @override
  State<NutritionGoalsScreen> createState() => _NutritionGoalsScreenState();
}

class _NutritionGoalsScreenState extends State<NutritionGoalsScreen> {
  final _calCtrl = TextEditingController();
  final _protCtrl = TextEditingController();
  final _carbsCtrl = TextEditingController();
  final _fatCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_calCtrl, _protCtrl, _carbsCtrl, _fatCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final goals = await WorkoutDatabase.instance.getNutritionGoals() ??
        NutritionGoals.defaults;
    if (mounted) {
      _calCtrl.text = goals.calories.round().toString();
      _protCtrl.text = goals.proteinG.round().toString();
      _carbsCtrl.text = goals.carbsG.round().toString();
      _fatCtrl.text = goals.fatG.round().toString();
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final goals = NutritionGoals(
      calories: double.parse(_calCtrl.text),
      proteinG: double.parse(_protCtrl.text),
      carbsG: double.parse(_carbsCtrl.text),
      fatG: double.parse(_fatCtrl.text),
    );
    await WorkoutDatabase.instance.saveNutritionGoals(goals);
    if (mounted) {
      popAfterFocusSettles(context, true);
    }
  }

  void _applyPreset(String label, double cal, double prot, double carbs, double fat) {
    _calCtrl.text = cal.round().toString();
    _protCtrl.text = prot.round().toString();
    _carbsCtrl.text = carbs.round().toString();
    _fatCtrl.text = fat.round().toString();
    setState(() {});
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
          onPressed: () => popAfterFocusSettles(context),
        ),
        title: const Text('Nutrition Goals',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Presets
                  const Text('Quick Presets',
                      style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _presetChip('Cut', 1800, 180, 150, 55),
                        const SizedBox(width: 8),
                        _presetChip('Maintenance', 2200, 160, 220, 70),
                        const SizedBox(width: 8),
                        _presetChip('Bulk', 3000, 200, 320, 90),
                        const SizedBox(width: 8),
                        _presetChip('High Protein', 2000, 220, 160, 60),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Calorie goal
                  _goalCard(
                    icon: Icons.local_fire_department_rounded,
                    color: const Color(0xFFFFD700),
                    label: 'Daily Calories',
                    unit: 'kcal',
                    ctrl: _calCtrl,
                  ),
                  const SizedBox(height: 12),

                  // Macro goals
                  _goalCard(
                    icon: Icons.fitness_center_rounded,
                    color: const Color(0xFF3498DB),
                    label: 'Protein',
                    unit: 'g',
                    ctrl: _protCtrl,
                    hint: 'Recommended: 1.6–2.2g per kg body weight',
                  ),
                  const SizedBox(height: 12),
                  _goalCard(
                    icon: Icons.grain_rounded,
                    color: const Color(0xFF2ECC71),
                    label: 'Carbohydrates',
                    unit: 'g',
                    ctrl: _carbsCtrl,
                  ),
                  const SizedBox(height: 12),
                  _goalCard(
                    icon: Icons.water_drop_rounded,
                    color: const Color(0xFFE67E22),
                    label: 'Fat',
                    unit: 'g',
                    ctrl: _fatCtrl,
                  ),

                  const SizedBox(height: 24),
                  _buildCalcRow(),
                  const SizedBox(height: 28),

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
                          : const Text('Save Goals',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _goalCard({
    required IconData icon,
    required Color color,
    required String label,
    required String unit,
    required TextEditingController ctrl,
    String? hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              SizedBox(
                width: 100,
                child: TextFormField(
                  controller: ctrl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Required';
                    return null;
                  },
                  decoration: InputDecoration(
                    suffix: Text(' $unit',
                        style: const TextStyle(
                            color: Color(0xFF555577), fontSize: 13)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    errorStyle: const TextStyle(height: 0.1, fontSize: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint,
                style:
                    const TextStyle(color: Color(0xFF444466), fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _presetChip(
      String label, double cal, double prot, double carbs, double fat) {
    return GestureDetector(
      onTap: () => _applyPreset(label, cal, prot, carbs, fat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1E1E35)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFFCCCCDD),
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildCalcRow() {
    final cal = int.tryParse(_calCtrl.text) ?? 0;
    final prot = int.tryParse(_protCtrl.text) ?? 0;
    final carbs = int.tryParse(_carbsCtrl.text) ?? 0;
    final fat = int.tryParse(_fatCtrl.text) ?? 0;
    final macroKcal = prot * 4 + carbs * 4 + fat * 9;
    final diff = cal - macroKcal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: diff.abs() < 50
                ? const Color(0xFF2ECC71).withValues(alpha: 0.3)
                : const Color(0xFF1E1E35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Macro calories total',
              style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
          Text(
            '$macroKcal kcal ${diff == 0 ? '✓' : diff > 0 ? '(${diff} under)' : '(${-diff} over)'}',
            style: TextStyle(
              color: diff.abs() < 50
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFE67E22),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
