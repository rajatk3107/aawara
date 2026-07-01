import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/workout/utils/samsung_link.dart';

void main() {
  group('isGymType', () {
    test('cardio/outdoor types are not gym-type', () {
      for (final t in [
        'WALKING',
        'RUNNING',
        'TRACK_RUNNING',
        'HIKING',
        'CYCLING',
        'SWIMMING',
        'ELLIPTICAL_TRAINER',
        'TREADMILL',
      ]) {
        expect(isGymType(t), isFalse, reason: t);
      }
    });

    test('strength/other types are gym-type', () {
      for (final t in [
        'WEIGHT_MACHINE',
        'OTHER_WORKOUT',
        'STRENGTH_TRAINING',
        'CIRCUIT_TRAINING',
      ]) {
        expect(isGymType(t), isTrue, reason: t);
      }
    });

    test('null/empty is not gym-type', () {
      expect(isGymType(null), isFalse);
      expect(isGymType(''), isFalse);
    });
  });
}
