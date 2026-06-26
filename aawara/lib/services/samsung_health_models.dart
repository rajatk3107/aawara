import 'dart:convert';

/// Dart models for the JSON the native Samsung Health bridge returns. Kept thin
/// + with the full `rawJson` retained so later analytics can mine fields we
/// don't model yet.

double? _d(Object? v) => v == null ? null : (v as num).toDouble();
int? _i(Object? v) => v == null ? null : (v as num).toInt();

class SamsungGeoPoint {
  final DateTime t;
  final double lat;
  final double lng;
  final double? alt;
  const SamsungGeoPoint(this.t, this.lat, this.lng, this.alt);
}

class SamsungExerciseSample {
  final DateTime t;
  final double? hr;
  final double? cadence;
  final double? power;
  final double? speed;
  const SamsungExerciseSample(
      {required this.t, this.hr, this.cadence, this.power, this.speed});
}

class SamsungExercise {
  final String uid;
  final String? exerciseType;
  final String? customTitle;
  final DateTime start;
  final DateTime end;
  final int durationSeconds;
  final double calories;
  final double? distance;
  final int? count;
  final double? meanHeartRate;
  final double? maxHeartRate;
  final double? minHeartRate;
  final double? meanSpeed;
  final double? maxSpeed;
  final double? vo2Max;
  final List<SamsungGeoPoint> route;
  final List<SamsungExerciseSample> samples;
  final String rawJson;

  const SamsungExercise({
    required this.uid,
    this.exerciseType,
    this.customTitle,
    required this.start,
    required this.end,
    required this.durationSeconds,
    required this.calories,
    this.distance,
    this.count,
    this.meanHeartRate,
    this.maxHeartRate,
    this.minHeartRate,
    this.meanSpeed,
    this.maxSpeed,
    this.vo2Max,
    this.route = const [],
    this.samples = const [],
    required this.rawJson,
  });

  factory SamsungExercise.fromJson(Map<dynamic, dynamic> m) {
    final start = DateTime.parse(m['startTime'] as String);
    final end = DateTime.parse(m['endTime'] as String);
    return SamsungExercise(
      uid: m['uid'] as String,
      exerciseType: m['exerciseType'] as String?,
      customTitle: m['customTitle'] as String?,
      start: start,
      end: end,
      durationSeconds:
          _i(m['durationSeconds']) ?? end.difference(start).inSeconds,
      calories: _d(m['calories']) ?? 0,
      distance: _d(m['distance']),
      count: _i(m['count']),
      meanHeartRate: _d(m['meanHeartRate']),
      maxHeartRate: _d(m['maxHeartRate']),
      minHeartRate: _d(m['minHeartRate']),
      meanSpeed: _d(m['meanSpeed']),
      maxSpeed: _d(m['maxSpeed']),
      vo2Max: _d(m['vo2Max']),
      route: [
        for (final r in (m['route'] as List? ?? []))
          SamsungGeoPoint(DateTime.parse(r['t'] as String),
              _d(r['lat'])!, _d(r['lng'])!, _d(r['alt'])),
      ],
      samples: [
        for (final l in (m['log'] as List? ?? []))
          SamsungExerciseSample(
            t: DateTime.parse(l['t'] as String),
            hr: _d(l['hr']),
            cadence: _d(l['cadence']),
            power: _d(l['power']),
            speed: _d(l['speed']),
          ),
      ],
      rawJson: jsonEncode(m),
    );
  }
}

class SamsungSleepStage {
  final String stage;
  final DateTime start;
  final DateTime end;
  const SamsungSleepStage(this.stage, this.start, this.end);
  int get minutes => end.difference(start).inMinutes;
}

class SamsungSleep {
  final String uid;
  final int? score;
  final DateTime start;
  final DateTime end;
  final int durationSeconds;
  final List<SamsungSleepStage> stages;
  final String rawJson;

  const SamsungSleep({
    required this.uid,
    this.score,
    required this.start,
    required this.end,
    required this.durationSeconds,
    this.stages = const [],
    required this.rawJson,
  });

  factory SamsungSleep.fromJson(Map<dynamic, dynamic> m) {
    final start = DateTime.parse(m['startTime'] as String);
    final end = DateTime.parse(m['endTime'] as String);
    return SamsungSleep(
      uid: m['uid'] as String,
      score: _i(m['score']),
      start: start,
      end: end,
      durationSeconds:
          _i(m['durationSeconds']) ?? end.difference(start).inSeconds,
      stages: [
        for (final s in (m['stages'] as List? ?? []))
          SamsungSleepStage(s['stage'] as String,
              DateTime.parse(s['start'] as String),
              DateTime.parse(s['end'] as String)),
      ],
      rawJson: jsonEncode(m),
    );
  }
}
