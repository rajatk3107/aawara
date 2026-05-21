class StepGoalPreset {
  final String label;
  final String description;
  final String contextTip;
  final int steps;
  final String emoji;

  const StepGoalPreset({
    required this.label,
    required this.description,
    required this.contextTip,
    required this.steps,
    required this.emoji,
  });
}

const List<StepGoalPreset> stepGoalPresets = [
  StepGoalPreset(
    label: 'Light',
    emoji: '🚶',
    steps: 5000,
    description: 'Recovery & rest days',
    contextTip: 'A gentle daily target — perfect for rest days '
        'or when starting out. ~3.8 km of walking.',
  ),
  StepGoalPreset(
    label: 'Moderate',
    emoji: '🏃',
    steps: 8000,
    description: 'Healthy daily activity',
    contextTip: 'A solid everyday target backed by recent research. '
        'Linked to reduced cardiovascular risk. ~6.1 km.',
  ),
  StepGoalPreset(
    label: 'Active',
    emoji: '⚡',
    steps: 10000,
    description: 'WHO recommended target',
    contextTip: 'The classic 10K target — roughly 45 min of brisk '
        'walking or ~7.6 km. Great for general fitness.',
  ),
  StepGoalPreset(
    label: 'Athlete',
    emoji: '🔥',
    steps: 15000,
    description: 'High activity lifestyle',
    contextTip: 'Very active! ~11.4 km per day. Ideal for weight '
        'loss and high cardiovascular fitness goals.',
  ),
  StepGoalPreset(
    label: 'Custom',
    emoji: '🎯',
    steps: 0,
    description: 'Set your own target',
    contextTip: '',
  ),
];
