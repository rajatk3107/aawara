import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_models.dart';
import '../../workout/database/workout_database.dart';

class TdeeCalculatorScreen extends StatefulWidget {
  const TdeeCalculatorScreen({super.key});

  @override
  State<TdeeCalculatorScreen> createState() => _TdeeCalculatorScreenState();
}

class _TdeeCalculatorScreenState extends State<TdeeCalculatorScreen> {
  final _db = WorkoutDatabase.instance;

  int _age = 25;
  bool _isMale = true;
  double _height = 170;
  double _weight = 70;
  int _activityLevel = 2; // 0–4
  int _goal = 1;           // 0=lose, 1=maintain, 2=gain

  bool _loading = true;
  bool _saving = false;

  static const _activityLabels = [
    'Sedentary',
    'Lightly active',
    'Moderately active',
    'Very active',
    'Extremely active',
  ];
  static const _activitySubtitles = [
    'Desk job, no exercise',
    '1–3 days/week',
    '3–5 days/week',
    '6–7 days/week',
    'Physical job + training',
  ];
  static const _activityMultipliers = [1.2, 1.375, 1.55, 1.725, 1.9];
  static const _goalLabels = ['Lose weight', 'Maintain weight', 'Gain muscle'];
  static const _goalOffsets = [-300.0, 0.0, 300.0];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final weight = await _db.getLatestBodyWeight();
    if (mounted) {
      setState(() {
        _age = prefs.getInt('tdee_age') ?? 25;
        _isMale = prefs.getBool('tdee_is_male') ?? true;
        _height = prefs.getDouble('tdee_height') ?? 170;
        _weight = weight ?? prefs.getDouble('tdee_weight') ?? 70;
        _activityLevel = prefs.getInt('tdee_activity') ?? 2;
        _goal = prefs.getInt('tdee_goal') ?? 1;
        _loading = false;
      });
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tdee_age', _age);
    await prefs.setBool('tdee_is_male', _isMale);
    await prefs.setDouble('tdee_height', _height);
    await prefs.setDouble('tdee_weight', _weight);
    await prefs.setInt('tdee_activity', _activityLevel);
    await prefs.setInt('tdee_goal', _goal);
  }

  // Mifflin-St Jeor
  double get _bmr {
    final base = 10 * _weight + 6.25 * _height - 5 * _age;
    return _isMale ? base + 5 : base - 161;
  }

  double get _tdee => _bmr * _activityMultipliers[_activityLevel];
  double get _targetCal => (_tdee + _goalOffsets[_goal]).clamp(1000, 9999);

  // Macro splits by goal: [protein%, carbs%, fat%]
  static const _splits = [
    [0.35, 0.35, 0.30], // lose
    [0.30, 0.40, 0.30], // maintain
    [0.30, 0.45, 0.25], // gain
  ];

  double get _proteinG => (_targetCal * _splits[_goal][0]) / 4;
  double get _carbsG => (_targetCal * _splits[_goal][1]) / 4;
  double get _fatG => (_targetCal * _splits[_goal][2]) / 9;

  Future<void> _applyGoals() async {
    setState(() => _saving = true);
    await _savePrefs();
    await _db.saveNutritionGoals(NutritionGoals(
      calories: _targetCal,
      proteinG: _proteinG,
      carbsG: _carbsG,
      fatG: _fatG,
    ));
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Goals updated ✓',
              style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF2A2A45),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        title: const Text('TDEE Calculator',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // ── Results Panel ──────────────────────────────────────
                _buildResultsPanel(),
                const SizedBox(height: 20),

                // ── Inputs ────────────────────────────────────────────
                _sectionHeader('Personal Info'),
                const SizedBox(height: 12),
                _buildSexToggle(),
                const SizedBox(height: 12),
                _buildStepper(
                  label: 'Age',
                  value: '$_age yrs',
                  onDecrement: _age > 15
                      ? () => setState(() { _age--; _savePrefs(); })
                      : null,
                  onIncrement: _age < 80
                      ? () => setState(() { _age++; _savePrefs(); })
                      : null,
                ),
                const SizedBox(height: 10),
                _buildStepper(
                  label: 'Height',
                  value: '${_height.toInt()} cm',
                  onDecrement: _height > 100
                      ? () => setState(() { _height -= 1; _savePrefs(); })
                      : null,
                  onIncrement: _height < 250
                      ? () => setState(() { _height += 1; _savePrefs(); })
                      : null,
                ),
                const SizedBox(height: 10),
                _buildStepper(
                  label: 'Weight',
                  value: '${_weight.toStringAsFixed(1)} kg',
                  onDecrement: _weight > 30
                      ? () => setState(() {
                            _weight = double.parse(
                                (_weight - 0.5).toStringAsFixed(1));
                            _savePrefs();
                          })
                      : null,
                  onIncrement: _weight < 300
                      ? () => setState(() {
                            _weight = double.parse(
                                (_weight + 0.5).toStringAsFixed(1));
                            _savePrefs();
                          })
                      : null,
                ),
                const SizedBox(height: 20),

                _sectionHeader('Activity Level'),
                const SizedBox(height: 12),
                _buildActivitySelector(),
                const SizedBox(height: 20),

                _sectionHeader('Goal'),
                const SizedBox(height: 12),
                _buildGoalSelector(),
                const SizedBox(height: 28),

                // ── Apply button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _applyGoals,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          const Color(0xFFFFD700).withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Apply as my goals',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
    );
  }

  // ─── Results Panel ──────────────────────────────────────────────────────────

  Widget _buildResultsPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${_targetCal.round()}',
            style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 48,
                fontWeight: FontWeight.bold,
                height: 1),
          ),
          const Text('kcal / day',
              style: TextStyle(color: Color(0xFF888899), fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              _MacroCard(
                label: 'Protein',
                grams: _proteinG,
                color: const Color(0xFF5DCAA5),
              ),
              const SizedBox(width: 8),
              _MacroCard(
                label: 'Carbs',
                grams: _carbsG,
                color: const Color(0xFFEF9F27),
              ),
              const SizedBox(width: 8),
              _MacroCard(
                label: 'Fat',
                grams: _fatG,
                color: const Color(0xFFF0997B),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'BMR: ${_bmr.round()} kcal  ·  TDEE: ${_tdee.round()} kcal',
            style: const TextStyle(
                color: Color(0xFF444466), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ─── Sex Toggle ─────────────────────────────────────────────────────────────

  Widget _buildSexToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          _SexChip(
            label: 'Male',
            icon: Icons.male_rounded,
            selected: _isMale,
            onTap: () => setState(() { _isMale = true; _savePrefs(); }),
            isLeft: true,
          ),
          _SexChip(
            label: 'Female',
            icon: Icons.female_rounded,
            selected: !_isMale,
            onTap: () => setState(() { _isMale = false; _savePrefs(); }),
            isLeft: false,
          ),
        ],
      ),
    );
  }

  // ─── Stepper ────────────────────────────────────────────────────────────────

  Widget _buildStepper({
    required String label,
    required String value,
    VoidCallback? onDecrement,
    VoidCallback? onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          _StepBtn(
              icon: Icons.remove_rounded,
              onTap: onDecrement),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          _StepBtn(
              icon: Icons.add_rounded,
              onTap: onIncrement),
        ],
      ),
    );
  }

  // ─── Activity Selector ──────────────────────────────────────────────────────

  Widget _buildActivitySelector() {
    return Column(
      children: List.generate(_activityLabels.length, (i) {
        final selected = _activityLevel == i;
        return GestureDetector(
          onTap: () => setState(() { _activityLevel = i; _savePrefs(); }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFFFD700).withValues(alpha: 0.08)
                  : const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                    : const Color(0xFF1E1E35),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_activityLabels[i],
                          style: TextStyle(
                              color: selected
                                  ? const Color(0xFFFFD700)
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text(_activitySubtitles[i],
                          style: const TextStyle(
                              color: Color(0xFF555577), fontSize: 12)),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFFFFD700), size: 18),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─── Goal Selector ──────────────────────────────────────────────────────────

  Widget _buildGoalSelector() {
    final icons = [
      Icons.trending_down_rounded,
      Icons.horizontal_rule_rounded,
      Icons.trending_up_rounded,
    ];
    return Row(
      children: List.generate(_goalLabels.length, (i) {
        final selected = _goal == i;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() { _goal = i; _savePrefs(); }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFFFD700).withValues(alpha: 0.1)
                    : const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF1E1E35),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(icons[i],
                      color: selected
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF555577),
                      size: 22),
                  const SizedBox(height: 6),
                  Text(
                    _goalLabels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF888899),
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _sectionHeader(String title) => Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
      );
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _MacroCard extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;

  const _MacroCard(
      {required this.label, required this.grams, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              '${grams.round()}g',
              style: TextStyle(
                  color: color, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF888899), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _SexChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isLeft;

  const _SexChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isLeft ? const Radius.circular(11) : Radius.zero,
              right: !isLeft ? const Radius.circular(11) : Radius.zero,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: selected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF555577),
                  size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: selected
                          ? const Color(0xFFFFD700)
                          : const Color(0xFF888899),
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap == null
              ? const Color(0xFF0D0D1A)
              : const Color(0xFFFFD700).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: onTap == null
                ? const Color(0xFF1E1E35)
                : const Color(0xFFFFD700).withValues(alpha: 0.4),
          ),
        ),
        child: Icon(icon,
            color: onTap == null
                ? const Color(0xFF333355)
                : const Color(0xFFFFD700),
            size: 18),
      ),
    );
  }
}
