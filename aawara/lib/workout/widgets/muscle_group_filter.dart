import 'package:flutter/material.dart';
import '../models/exercise.dart';

class MuscleGroupFilter extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const MuscleGroupFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Chip(label: 'All', selected: selected == null, onTap: () => onChanged(null)),
          ...kMuscleGroups.map(
            (g) => _Chip(
              label: g,
              selected: selected == g,
              onTap: () => onChanged(selected == g ? null : g),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFD700) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFFD700) : const Color(0xFF333355),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.black : const Color(0xFFCCCCDD),
          ),
        ),
      ),
    );
  }
}
