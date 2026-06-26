import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/services/samsung_health_models.dart';

void main() {
  group('SamsungExercise.fromJson', () {
    test('parses core fields, metrics, route and log', () {
      final e = SamsungExercise.fromJson({
        'uid': 'abc',
        'exerciseType': 'RUNNING',
        'customTitle': 'Morning run',
        'startTime': '2026-06-25T05:30:00Z',
        'endTime': '2026-06-25T06:10:00Z',
        'durationSeconds': 2400,
        'calories': 312.5,
        'distance': 5200.0,
        'meanHeartRate': 148.0,
        'maxHeartRate': 171.0,
        'route': [
          {'t': '2026-06-25T05:30:00Z', 'lat': 12.9, 'lng': 77.6, 'alt': 900.0}
        ],
        'log': [
          {'t': '2026-06-25T05:31:00Z', 'hr': 140.0, 'speed': 2.6}
        ],
      });
      expect(e.uid, 'abc');
      expect(e.exerciseType, 'RUNNING');
      expect(e.customTitle, 'Morning run');
      expect(e.start, DateTime.utc(2026, 6, 25, 5, 30));
      expect(e.durationSeconds, 2400);
      expect(e.calories, 312.5);
      expect(e.meanHeartRate, 148.0);
      expect(e.route.length, 1);
      expect(e.route.first.lat, 12.9);
      expect(e.samples.length, 1);
      expect(e.samples.first.hr, 140.0);
      // raw JSON retained for analytics
      expect(e.rawJson.contains('RUNNING'), isTrue);
    });

    test('tolerates missing optional fields', () {
      final e = SamsungExercise.fromJson({
        'uid': 'x',
        'startTime': '2026-06-25T05:30:00Z',
        'endTime': '2026-06-25T06:00:00Z',
        'calories': 100.0,
      });
      expect(e.meanHeartRate, isNull);
      expect(e.route, isEmpty);
      expect(e.samples, isEmpty);
    });
  });

  group('SamsungSleep.fromJson', () {
    test('parses score and stages', () {
      final s = SamsungSleep.fromJson({
        'uid': 'n1',
        'score': 79,
        'startTime': '2026-06-24T22:40:00Z',
        'endTime': '2026-06-25T06:01:00Z',
        'durationSeconds': 26460,
        'stages': [
          {'stage': 'LIGHT', 'start': '2026-06-24T22:40:00Z', 'end': '2026-06-24T23:00:00Z'},
          {'stage': 'DEEP', 'start': '2026-06-24T23:00:00Z', 'end': '2026-06-24T23:20:00Z'},
        ],
      });
      expect(s.uid, 'n1');
      expect(s.score, 79);
      expect(s.stages.length, 2);
      expect(s.stages.first.stage, 'LIGHT');
      expect(s.stages.first.minutes, 20);
    });
  });
}
