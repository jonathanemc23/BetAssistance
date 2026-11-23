import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/logic/leg_linker.dart';
import 'package:bank_track/ui/slip_import.dart';
import 'package:flutter/material.dart';
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

  choiceTests();
}

void choiceTests() {
  Match game(String id, String home) => Match(
        id: id,
        league: const League('eng.1', 'Premier League'),
        kickoff: DateTime.utc(2026, 11, 23, 15),
        home: Team(home, home, null, null),
        away: const Team('Arsenal', 'Arsenal', null, null),
        state: MatchState.scheduled,
        detail: '',
      );

  testWidgets('the user picks the match when several fit, or none', (tester) async {
    const leg = ParlayLeg(selection: 'Arsenal', event: 'Manchester vs Arsenal', odds: 2.4);
    final links = [
      LegLink(leg, [MatchCandidate(game('1', 'Manchester United'), 0.9), MatchCandidate(game('2', 'Manchester City'), 0.9)]),
      const LegLink(leg, []),
    ];
    List<ParlayLeg>? out;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => out = await chooseMatches(context, links),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Which match is it?'), findsOneWidget);
    expect(find.text('Manchester United vs Arsenal'), findsOneWidget);
    await tester.tap(find.text('Manchester City vs Arsenal'));
    await tester.pumpAndSettle();
    expect(out!.map((l) => (l.isLinked, l.matchId, l.selection)), [(true, '2', 'Arsenal to win'), (false, null, 'Arsenal')]);
  });
}
