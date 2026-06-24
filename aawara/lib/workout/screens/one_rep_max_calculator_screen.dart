import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/one_rep_max.dart';

class OneRepMaxCalculatorScreen extends StatefulWidget {
  const OneRepMaxCalculatorScreen({super.key});

  @override
  State<OneRepMaxCalculatorScreen> createState() =>
      _OneRepMaxCalculatorScreenState();
}

class _OneRepMaxCalculatorScreenState extends State<OneRepMaxCalculatorScreen> {
  final _weightCtrl = TextEditingController(text: '60');
  final _repsCtrl = TextEditingController(text: '5');

  double get _weight => double.tryParse(_weightCtrl.text.trim()) ?? 0;
  int get _reps => int.tryParse(_repsCtrl.text.trim()) ?? 0;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  void _bumpWeight(double delta) {
    final next = (_weight + delta).clamp(0, 1000);
    // Drop a trailing .0 so the field stays tidy for whole numbers.
    _weightCtrl.text =
        next == next.roundToDouble() ? next.toInt().toString() : next.toString();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _bumpReps(int delta) {
    final next = (_reps + delta).clamp(1, 30);
    _repsCtrl.text = next.toString();
    HapticFeedback.selectionClick();
    setState(() {});
  }

  String _fmtWeight(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final oneRm = epleyOneRepMax(_weight, _reps);
    final table = repMaxTable(oneRm);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('1RM Calculator',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _buildInputCard(),
          const SizedBox(height: 16),
          if (oneRm > 0)
            _buildResultCard(oneRm, table)
          else
            _buildPrompt(),
          const SizedBox(height: 16),
          const Text(
            'Estimated with the Epley formula. Estimates are most accurate at 1–10 reps.',
            style: TextStyle(color: Color(0xFF555577), fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        children: [
          _buildField(
            label: 'WEIGHT (KG)',
            controller: _weightCtrl,
            decimal: true,
            onMinus: () => _bumpWeight(-2.5),
            onPlus: () => _bumpWeight(2.5),
          ),
          const SizedBox(height: 16),
          _buildField(
            label: 'REPS',
            controller: _repsCtrl,
            decimal: false,
            onMinus: () => _bumpReps(-1),
            onPlus: () => _bumpReps(1),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required bool decimal,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                keyboardType: TextInputType.numberWithOptions(decimal: decimal),
                inputFormatters: [
                  decimal
                      ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      : FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  border: InputBorder.none,
                  hintText: '0',
                  hintStyle: TextStyle(color: Color(0xFF444466)),
                ),
              ),
            ],
          ),
        ),
        _stepperButton(Icons.remove_rounded, onMinus),
        const SizedBox(width: 10),
        _stepperButton(Icons.add_rounded, onPlus),
      ],
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A45)),
        ),
        child: Icon(icon, color: const Color(0xFFFFD700), size: 22),
      ),
    );
  }

  Widget _buildResultCard(double oneRm, List<RepTarget> table) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ESTIMATED 1RM',
              style: TextStyle(
                  color: Color(0xFF888899),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmtWeight(oneRm),
                  style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 40,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('kg',
                    style: TextStyle(
                        color: Color(0xFF888899),
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFF1E1E35)),
          const SizedBox(height: 12),
          // Table header
          const Row(
            children: [
              Expanded(
                  flex: 2,
                  child: Text('REPS',
                      style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8))),
              Expanded(
                  flex: 2,
                  child: Text('% 1RM',
                      style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8))),
              Expanded(
                  flex: 3,
                  child: Text('WEIGHT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Color(0xFF888899),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8))),
            ],
          ),
          const SizedBox(height: 4),
          for (final t in table) _buildTableRow(t),
        ],
      ),
    );
  }

  Widget _buildTableRow(RepTarget t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('${t.reps}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text('${t.percent}%',
                style: const TextStyle(color: Color(0xFF888899), fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text('${_fmtWeight(t.weight)} kg',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: const Text('Enter a weight and reps to estimate your 1RM',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF555577), fontSize: 13)),
    );
  }
}
