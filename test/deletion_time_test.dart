import 'package:flutter_test/flutter_test.dart';
import 'package:pensiune_app/main.dart';

void main() {
  final now = DateTime(2026, 11, 24, 16, 49);
  Item booking({required DateTime created, DateTime? start, bool validated = false}) => Item(
        syncId: 's1',
        number: 1,
        name: 'Camera 1',
        description: '',
        createdAt: created,
        startsAt: start,
        validated: validated,
      );

  test('anularea automată primește ora termenului de 24 h, nu ora deschiderii', () {
    final created = DateTime(2026, 11, 22, 10);
    final item = booking(created: created, start: DateTime(2026, 11, 27, 14));
    expect(queuedDeletionTime(item, now: now), DateTime(2026, 11, 23, 10));
  });

  test('ștergere înainte de termen sau rezervare validată: ora curentă', () {
    expect(queuedDeletionTime(booking(created: DateTime(2026, 11, 24, 9)), now: now), now);
    expect(
        queuedDeletionTime(
            booking(created: DateTime(2026, 11, 20), start: DateTime(2026, 11, 27), validated: true),
            now: now),
        now);
  });

  test('termenul după check-in nu contează (sejurul începuse)', () {
    final item = booking(created: DateTime(2026, 11, 20, 10), start: DateTime(2026, 11, 20, 14));
    expect(queuedDeletionTime(item, now: now), now);
  });
}
