/// Seconds left on an in-progress rest, derived from its wall-clock end time.
///
/// The rest countdown is anchored to an absolute end timestamp (persisted in
/// SharedPreferences) rather than counting in-memory ticks, so it stays correct
/// when the logging screen is closed/reopened or the app is backgrounded.
///
/// Returns 0 when there is no active rest ([endTime] is null) or the rest has
/// already elapsed. A partial trailing second rounds up so the final second is
/// still displayed.
int restRemainingSeconds(DateTime? endTime, DateTime now) {
  if (endTime == null) return 0;
  final ms = endTime.difference(now).inMilliseconds;
  if (ms <= 0) return 0;
  return (ms / 1000).ceil();
}
