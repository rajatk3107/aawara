/// A single night's sleep, cached from Health Connect (or entered manually).
/// Keyed by [date] = the wake day (YYYY-MM-DD).
class SleepSession {
  final String date;
  final String? startIso;
  final String? endIso;
  final int totalMinutes;
  final int asleepMinutes;
  final int awakeMinutes;
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int score;
  final double? hrAvg;
  final double? hrMin;
  final double? spo2Avg;
  final double? spo2Min;
  final double? respAvg;
  final String source; // 'health_connect' | 'manual'
  final String? stagesJson; // ordered [{stage,start,end}] for the hypnogram

  const SleepSession({
    required this.date,
    this.startIso,
    this.endIso,
    required this.totalMinutes,
    required this.asleepMinutes,
    this.awakeMinutes = 0,
    this.lightMinutes = 0,
    this.deepMinutes = 0,
    this.remMinutes = 0,
    this.score = 0,
    this.hrAvg,
    this.hrMin,
    this.spo2Avg,
    this.spo2Min,
    this.respAvg,
    this.source = 'health_connect',
    this.stagesJson,
  });

  bool get hasStages =>
      lightMinutes + deepMinutes + remMinutes + awakeMinutes > 0;

  Map<String, dynamic> toMap() => {
        'date': date,
        'start_iso': startIso,
        'end_iso': endIso,
        'total_minutes': totalMinutes,
        'asleep_minutes': asleepMinutes,
        'awake_minutes': awakeMinutes,
        'light_minutes': lightMinutes,
        'deep_minutes': deepMinutes,
        'rem_minutes': remMinutes,
        'score': score,
        'hr_avg': hrAvg,
        'hr_min': hrMin,
        'spo2_avg': spo2Avg,
        'spo2_min': spo2Min,
        'resp_avg': respAvg,
        'source': source,
        'stages_json': stagesJson,
      };

  factory SleepSession.fromMap(Map<String, dynamic> m) => SleepSession(
        date: m['date'] as String,
        startIso: m['start_iso'] as String?,
        endIso: m['end_iso'] as String?,
        totalMinutes: (m['total_minutes'] as int?) ?? 0,
        asleepMinutes: (m['asleep_minutes'] as int?) ?? 0,
        awakeMinutes: (m['awake_minutes'] as int?) ?? 0,
        lightMinutes: (m['light_minutes'] as int?) ?? 0,
        deepMinutes: (m['deep_minutes'] as int?) ?? 0,
        remMinutes: (m['rem_minutes'] as int?) ?? 0,
        score: (m['score'] as int?) ?? 0,
        hrAvg: (m['hr_avg'] as num?)?.toDouble(),
        hrMin: (m['hr_min'] as num?)?.toDouble(),
        spo2Avg: (m['spo2_avg'] as num?)?.toDouble(),
        spo2Min: (m['spo2_min'] as num?)?.toDouble(),
        respAvg: (m['resp_avg'] as num?)?.toDouble(),
        source: (m['source'] as String?) ?? 'health_connect',
        stagesJson: m['stages_json'] as String?,
      );
}
