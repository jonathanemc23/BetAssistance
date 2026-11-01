import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/ui/slip_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 1, 15, 30);

  test('one selection read from a slip becomes a single bet', () {
    final bet = slipBet([const ParlayLeg(selection: 'Millonarios', event: 'Millonarios - Santa Fe', odds: 2.05)], 5000, now);
    expect(bet.type, BetType.single);
    expect((bet.selection, bet.event, bet.odds, bet.stake, bet.date), ('Millonarios', 'Millonarios - Santa Fe', 2.05, 5000.0, '2026-11-01'));
    expect(bet.legs, isEmpty);
  });

  test('several selections become a parlay with the combined odds', () {
    final bet = slipBet(const [
      ParlayLeg(selection: 'Millonarios', event: 'Millonarios - Santa Fe', odds: 2.05),
      ParlayLeg(selection: 'Más de 2.5', event: 'Junior - Nacional', odds: 1.80),
    ], 10000, now);
    expect(bet.type, BetType.parlay);
    expect(bet.legs.map((l) => (l.selection, l.odds)), [('Millonarios', 2.05), ('Más de 2.5', 1.80)]);
    expect(bet.odds, closeTo(3.69, 0.001));
    expect(bet.stake, 10000);
  });
}
