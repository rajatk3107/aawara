import 'package:flutter/material.dart';
import '../models/exercise.dart';

const Map<String, Color> _muscleColors = {
  'Chest': Color(0xFFE74C3C),
  'Back': Color(0xFF3498DB),
  'Shoulders': Color(0xFF9B59B6),
  'Arms': Color(0xFFE67E22),
  'Legs': Color(0xFF2ECC71),
  'Core': Color(0xFFF39C12),
  'Cardio': Color(0xFF1ABC9C),
  'Full Body': Color(0xFFFFD700),
};

const Map<String, IconData> _equipmentIcons = {
  'Barbell': Icons.fitness_center,
  'Dumbbell': Icons.sports_gymnastics,
  'Cable': Icons.cable,
  'Machine': Icons.precision_manufacturing,
  'Bodyweight': Icons.accessibility_new,
  'Kettlebell': Icons.sports_mma,
  'Resistance Band': Icons.loop,
  'Other': Icons.sports,
};

Color muscleColor(String group) =>
    _muscleColors[group] ?? const Color(0xFFFFD700);

IconData equipmentIcon(String equipment) =>
    _equipmentIcons[equipment] ?? Icons.fitness_center;

class ExerciseTile extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool compact;

  const ExerciseTile({
    super.key,
    required this.exercise,
    this.onTap,
    this.trailing,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = muscleColor(exercise.muscleGroup);
    return Material(
      color: const Color(0xFF1A1A2E),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 10 : 14,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(equipmentIcon(exercise.equipment),
                    color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _Tag(exercise.muscleGroup, color),
                          const SizedBox(width: 6),
                          _Tag(exercise.equipment,
                              const Color(0xFF888899)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
