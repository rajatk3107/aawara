import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/services/supplement_payload.dart';

void main() {
  group('supplement notification payload', () {
    test('round-trips id, name and dose', () {
      final encoded = encodeSupplementPayload(id: 7, name: 'Creatine', dose: '5 g');
      final decoded = decodeSupplementPayload(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.id, 7);
      expect(decoded.name, 'Creatine');
      expect(decoded.dose, '5 g');
    });

    test('round-trips an empty dose as null', () {
      final encoded = encodeSupplementPayload(id: 3, name: 'D3+K2', dose: null);
      final decoded = decodeSupplementPayload(encoded);
      expect(decoded!.id, 3);
      expect(decoded.name, 'D3+K2');
      expect(decoded.dose, isNull);
    });

    test('sanitizes the pipe delimiter out of name and dose', () {
      final encoded =
          encodeSupplementPayload(id: 1, name: 'A|B', dose: '1|2 g');
      final decoded = decodeSupplementPayload(encoded);
      expect(decoded!.id, 1);
      // The delimiter must not corrupt parsing; remaining fields stay intact.
      expect(decoded.name.contains('|'), isFalse);
      expect(decoded.dose, isNotNull);
    });

    test('returns null for a non-supplement payload', () {
      expect(decodeSupplementPayload(null), isNull);
      expect(decodeSupplementPayload(''), isNull);
      expect(decodeSupplementPayload('workout|1'), isNull);
      expect(decodeSupplementPayload('supp|notanumber|X|'), isNull);
    });
  });
}
