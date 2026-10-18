import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/odds_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final match = Match(
    id: '401878771',
    league: const League('eng.1', 'Premier League'),
    kickoff: DateTime.utc(2026, 10, 18, 19),
    home: const Team('Everton', 'Everton', null, null),
    away: const Team('Chelsea', 'Chelsea', null, null),
    state: MatchState.scheduled,
    detail: '',
  );

  test('reads the opening line next to the current price', () {
    final d = parseMatchDetails(File('test/data/espn_summary_pre.json').readAsStringSync());
    final dk = d.odds.firstWhere((o) => o.opening != null);
    expect(dk.provider, 'DraftKings');
    // Everton opened +175 and is now +215; Chelsea +130 -> +120.
    expect((dk.opening!.home, dk.home), (2.75, 3.15));
    expect((dk.opening!.away, dk.away), (2.3, 2.2));
    expect(dk.opening!.over, closeTo(1.606, 0.001));

    final mv = marketMove(match, d.odds, const [])!;
    expect(mv.fromOpening, isTrue);
    expect(mv.outcomes.map((o) => o.label), ['Everton', 'Draw', 'Chelsea']);
    expect(mv.backed!.label, 'Chelsea');
    expect(mv.outcomes.first.shift, lessThan(-3)); // Everton drifted
    final total = mv.outcomes.fold<double>(0, (a, o) => a + o.chanceTo);
    expect(total, closeTo(1, 1e-9)); // margin taken out
  });

  test('without an opening line it uses the prices this phone saw', () {
    const odds = [MatchOdds(home: 2.0, draw: 3.4, away: 3.8, provider: 'Bet 365')];
    expect(marketMove(match, odds, const []), isNull);
    final h = [
      OddsSnapshot(at: DateTime.utc(2026, 10, 17, 9), provider: 'Bet 365', home: 2.4, draw: 3.3, away: 3.0),
      OddsSnapshot(at: DateTime.utc(2026, 10, 18, 9), provider: 'Bet 365', home: 2.0, draw: 3.4, away: 3.8),
    ];
    final mv = marketMove(match, odds, h)!;
    expect(mv.fromOpening, isFalse);
    expect(mv.since, DateTime.utc(2026, 10, 17, 9));
    expect(mv.backed!.label, 'Everton');
    expect(mv.flat, isFalse);

    final still = marketMove(match, odds, [h.last, h.last])!;
    expect(still.flat, isTrue);
    expect(still.backed, isNull);
  });

  test('tracks the provider with the most prices', () {
    expect(trackedOdds(const []), isNull);
    expect(trackedOdds(const [MatchOdds(home: 2, draw: null, away: null)]), isNull);
    expect(
      trackedOdds(const [
        MatchOdds(home: 2, draw: null, away: 3, provider: 'a'),
        MatchOdds(home: 2, draw: 3, away: 3, provider: 'b'),
      ])!.provider,
      'b',
    );
  });
}
