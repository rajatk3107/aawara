import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/workout_log.dart';

class SetLogTile extends StatefulWidget {
  final SetLog setLog;
  final int setIndex;
  final String? previousHint;
  final ValueChanged<SetLog> onChanged;
  final VoidCallback onDelete;

  const SetLogTile({
    super.key,
    required this.setLog,
    required this.setIndex,
    this.previousHint,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<SetLogTile> createState() => _SetLogTileState();
}

class _SetLogTileState extends State<SetLogTile> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _repsCtrl;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController(
      text: widget.setLog.weight != null
          ? _fmt(widget.setLog.weight!)
          : '',
    );
    _repsCtrl = TextEditingController(
      text: widget.setLog.reps?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == v.truncate() ? v.toInt().toString() : v.toString();

  void _emit() {
    final w = double.tryParse(_weightCtrl.text.trim());
    final r = int.tryParse(_repsCtrl.text.trim());
    widget.onChanged(widget.setLog.copyWith(weight: w, reps: r));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${widget.setIndex + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              controller: _weightCtrl,
              hint: widget.previousHint != null ? _prevWeight() : 'kg',
              suffix: 'kg',
              decimal: true,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          const Text('×', style: TextStyle(color: Color(0xFF888899), fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              controller: _repsCtrl,
              hint: widget.previousHint != null ? _prevReps() : 'reps',
              suffix: 'reps',
              decimal: false,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF888899)),
            onPressed: widget.onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  String _prevWeight() {
    if (widget.previousHint == null) return 'kg';
    final parts = widget.previousHint!.split('×');
    return parts.isNotEmpty ? parts[0].trim() : 'kg';
  }

  String _prevReps() {
    if (widget.previousHint == null) return 'reps';
    final parts = widget.previousHint!.split('×');
    return parts.length > 1 ? parts[1].trim() : 'reps';
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String suffix;
  final bool decimal;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.controller,
    required this.hint,
    required this.suffix,
    required this.decimal,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[\d.]') : RegExp(r'\d')),
      ],
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555566), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF333355)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF333355)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}
