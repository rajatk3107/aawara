/// One-rep-max estimation and rep/percentage tables.
///
/// Uses the Epley formula `1RM = weight × (1 + reps/30)`, the same model the
/// rest of the app uses for PRs and progress charts, so estimates stay
/// consistent across screens.
library;

/// Estimated one-rep max for lifting [weight] (kg) for [reps] reps.
/// A true single (reps == 1) returns the weight itself — that *is* the 1RM —
/// rather than Epley's slight over-estimate at one rep. Returns 0 for
/// non-positive inputs.
double epleyOneRepMax(double weight, int reps) {
  if (weight <= 0 || reps <= 0) return 0;
  if (reps == 1) return weight;
  return weight * (1 + reps / 30.0);
}

/// One row of the rep/percentage table.
class RepTarget {
  final int reps;
  final int percent; // % of 1RM, rounded to a whole number
  final double weight; // kg, rounded to the nearest 0.5

  const RepTarget({
    required this.reps,
    required this.percent,
    required this.weight,
  });
}

/// Target rep counts shown in the table (the headline 1RM covers reps == 1).
const _repTargets = [2, 3, 5, 8, 10, 12];

double _roundToHalf(double v) => (v * 2).round() / 2;

/// For a given [oneRm], the estimated weight you could lift for each working-rep
/// target, by Epley inverse: `weight = 1RM / (1 + reps/30)`. Returns an empty
/// list for a non-positive 1RM.
List<RepTarget> repMaxTable(double oneRm) {
  if (oneRm <= 0) return const [];
  return _repTargets.map((reps) {
    final ratio = 1 / (1 + reps / 30.0);
    return RepTarget(
      reps: reps,
      percent: (ratio * 100).round(),
      weight: _roundToHalf(oneRm * ratio),
    );
  }).toList();
}
