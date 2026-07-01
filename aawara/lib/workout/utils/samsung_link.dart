/// Whether a Samsung exercise type counts as a "gym-type" session — i.e. the
/// kind you'd hand-log with sets & reps (strength/other), as opposed to
/// auto-detected cardio (walking, running, hiking, cycling, swimming). Used by
/// the historical date-based linker so a logged gym workout links only to a gym
/// session that day, never to an evening walk. Pure + unit-tested.
bool isGymType(String? exerciseType) {
  if (exerciseType == null || exerciseType.isEmpty) return false;
  final t = exerciseType.toUpperCase();
  const cardio = ['WALK', 'RUN', 'HIK', 'CYCL', 'SWIM', 'ELLIPTICAL', 'TREADMILL'];
  return !cardio.any(t.contains);
}
