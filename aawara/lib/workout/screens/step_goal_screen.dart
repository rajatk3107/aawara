import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/step_goal_presets.dart';
import '../../services/step_tracking_service.dart';

class StepGoalScreen extends StatefulWidget {
  final bool isFirstSetup;

  const StepGoalScreen({super.key, this.isFirstSetup = false});

  @override
  State<StepGoalScreen> createState() => _StepGoalScreenState();
}

class _StepGoalScreenState extends State<StepGoalScreen> {
  int _selectedPresetIndex = 1; // Moderate (8000) by default
  int _customSteps = 8000;
  int _displayedSteps = 8000;
  bool _saving = false;

  final _customCtrl = TextEditingController();
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentGoal();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    _longPressTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('step_goal') ?? 8000;
    setState(() {
      _displayedSteps = saved;
      // Match to preset
      final idx = stepGoalPresets.indexWhere((p) => p.steps == saved);
      if (idx >= 0) {
        _selectedPresetIndex = idx;
      } else {
        _selectedPresetIndex = stepGoalPresets.length - 1; // Custom
        _customSteps = saved;
        _customCtrl.text = saved.toString();
      }
    });
  }

  StepGoalPreset get _selectedPreset => stepGoalPresets[_selectedPresetIndex];

  int get _effectiveSteps =>
      _selectedPreset.steps > 0 ? _selectedPreset.steps : _customSteps;

  void _selectPreset(int index) {
    setState(() {
      _selectedPresetIndex = index;
      if (stepGoalPresets[index].steps > 0) {
        _displayedSteps = stepGoalPresets[index].steps;
      } else {
        _displayedSteps = _customSteps;
      }
    });
  }

  void _adjustCustom(int delta) {
    setState(() {
      _customSteps = (_customSteps + delta).clamp(1000, 50000);
      _displayedSteps = _customSteps;
      _customCtrl.text = _customSteps.toString();
    });
  }

  void _startLongPress(int delta) {
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _adjustCustom(delta);
    });
  }

  void _stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  String _contextTip() {
    if (_selectedPreset.steps == 0) {
      // Custom — show live estimate
      final dist = (_customSteps * 0.000762).toStringAsFixed(1);
      final cal = (_customSteps * 0.038).round();
      return '~$dist km  ·  ~$cal kcal per day';
    }
    return _selectedPreset.contextTip;
  }

  Future<void> _save() async {
    final goal = _effectiveSteps;
    if (goal < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Minimum goal is 1,000 steps'),
        backgroundColor: Color(0xFF1A1A2E),
      ));
      return;
    }
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('step_goal', goal);

    if (widget.isFirstSetup) {
      final enabled = await StepTrackingService.enable();
      if (!mounted) return;
      if (!enabled) {
        setState(() => _saving = false);
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(goal);
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Set Step Goal',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                const SizedBox(height: 16),
                _buildHeader(),
                const SizedBox(height: 28),
                _buildPresetList(),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: _selectedPreset.steps == 0
                      ? _buildCustomInput()
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                _buildContextTip(),
                const SizedBox(height: 24),
              ],
            ),
          ),
          _buildBottomButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            _fmt(_displayedSteps),
            key: ValueKey(_displayedSteps),
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 56,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
        const Text('steps per day',
            style: TextStyle(color: Color(0xFF888899), fontSize: 14)),
        const SizedBox(height: 8),
        const Text(
          'Choose a daily target that fits your lifestyle',
          style: TextStyle(color: Color(0xFF555577), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPresetList() {
    return Column(
      children: List.generate(stepGoalPresets.length, (i) {
        final preset = stepGoalPresets[i];
        final isSelected = _selectedPresetIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => _selectPreset(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF2A2A3E),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                          : const Color(0xFF0D0D1A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(preset.emoji,
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preset.label,
                            style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFCCCCDD),
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        Text(preset.description,
                            style: const TextStyle(
                                color: Color(0xFF555577), fontSize: 12)),
                      ],
                    ),
                  ),
                  if (preset.steps > 0)
                    Text(
                      _fmt(preset.steps),
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFFFFD700)
                            : const Color(0xFF555577),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCustomInput() {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your goal',
              style: TextStyle(color: Color(0xFF888899), fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepButton(
                label: '−',
                onTap: () => _adjustCustom(-500),
                onLongPressStart: () => _startLongPress(-1000),
                onLongPressEnd: _stopLongPress,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A2E),
                        title: const Text('Enter step goal',
                            style: TextStyle(color: Colors.white)),
                        content: TextField(
                          controller: _customCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: const TextStyle(color: Colors.white),
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: '1000 – 50000',
                            hintStyle:
                                TextStyle(color: Color(0xFF555577)),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(color: Color(0xFF888899))),
                          ),
                          TextButton(
                            onPressed: () {
                              final v = int.tryParse(_customCtrl.text);
                              if (v != null) {
                                setState(() {
                                  _customSteps = v.clamp(1000, 50000);
                                  _displayedSteps = _customSteps;
                                  _customCtrl.text =
                                      _customSteps.toString();
                                });
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('OK',
                                style: TextStyle(
                                    color: Color(0xFFFFD700))),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      Text(
                        _fmt(_customSteps),
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Text('tap to type',
                          style: TextStyle(
                              color: Color(0xFF555577), fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _stepButton(
                label: '+',
                onTap: () => _adjustCustom(500),
                onLongPressStart: () => _startLongPress(1000),
                onLongPressEnd: _stopLongPress,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '~${(_customSteps * 0.000762).toStringAsFixed(1)} km  ·  ~${(_customSteps * 0.038).round()} kcal per day',
              style: const TextStyle(
                  color: Color(0xFF555577), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required String label,
    required VoidCallback onTap,
    required VoidCallback onLongPressStart,
    required VoidCallback onLongPressEnd,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onLongPressStart(),
      onLongPressEnd: (_) => onLongPressEnd(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF333355)),
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w300)),
        ),
      ),
    );
  }

  Widget _buildContextTip() {
    final tip = _contextTip();
    if (tip.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(tip),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Color(0xFF555577), size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tip,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
              : Text(
                  widget.isFirstSetup ? 'Start Tracking' : 'Save Goal',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
      ),
    );
  }
}
