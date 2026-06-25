import 'package:flutter_test/flutter_test.dart';
import 'package:aawara/services/pending_supplement_taken.dart';

void main() {
  group('pending supplement-taken queue', () {
    test('formats a line as id,date', () {
      expect(formatPendingTakenLine(7, '2026-06-24'), '7,2026-06-24');
    });

    test('round-trips formatted lines', () {
      final contents =
          '${formatPendingTakenLine(7, '2026-06-24')}\n${formatPendingTakenLine(3, '2026-06-23')}\n';
      final parsed = parsePendingTaken(contents);
      expect(parsed.length, 2);
      expect(parsed[0].id, 7);
      expect(parsed[0].date, '2026-06-24');
      expect(parsed[1].id, 3);
      expect(parsed[1].date, '2026-06-23');
    });

    test('ignores blank and malformed lines', () {
      const contents = '7,2026-06-24\n\n  \ngarbage\nx,2026-06-24\n9,2026-06-25';
      final parsed = parsePendingTaken(contents);
      expect(parsed.map((e) => e.id).toList(), [7, 9]);
      expect(parsed.last.date, '2026-06-25');
    });

    test('returns empty for empty contents', () {
      expect(parsePendingTaken(''), isEmpty);
    });
  });
}
