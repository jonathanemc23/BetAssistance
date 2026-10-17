import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/logic/parlay_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final api = FixturesApi(
    client: MockClient((req) async => http.Response.bytes(
          File('test/data/espn_summary_pre.json').readAsBytesSync(),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        )),
  );
  final match = Match(
    id: '401878771',
    league: const League('eng.1', 'Premier League'),
    kickoff: DateTime.utc(2026, 10, 18, 19),
    home: const Team('Everton', 'Everton', null, null),
    away: const Team('Chelsea', 'Chelsea', null, null),
    state: MatchState.scheduled,
    detail: '',
  );
  final checker = DataParlayChecker(api, now: () => DateTime.utc(2026, 10, 17, 12));
  Parlay parlay(List<ParlayLeg> legs) => Parlay(name: 'Test', legs: legs, created: 'x', updated: 'x');

  test('linked legs are priced against the market, typed ones by price only', () async {
    final c = await checker.check(parlay([
      ParlayLeg.fromMatch(match, 'Chelsea to win', 3.0),
      const ParlayLeg(selection: 'Millonarios to win', event: 'Millonarios vs Nacional', odds: 2.0),
    ]));
    expect(c.legs, hasLength(2));
    // 3.00 on Chelsea is well above the market, so it reads as a good price.
    expect(c.legs.first.verdict, 'Good price');
    expect(c.legs.first.tone, LegTone.good);
    expect(c.legs.first.lines.any((l) => l.startsWith('Market chance')), isTrue);
    expect(c.legs.first.lines.any((l) => l.startsWith('Chelsea:')), isTrue);
    expect(c.legs.last.verdict, 'Price only');
    expect(c.summary.first, '2 selections at combined odds 6.00.');
    expect(c.summary.any((s) => s.startsWith('Weakest leg')), isTrue);
    expect(c.summary.last, 'This is a reading of the data, not a guarantee.');
  });

  test('a short price is below market, and same-match picks are flagged', () async {
    final c = await checker.check(parlay([
      ParlayLeg.fromMatch(match, 'Chelsea to win', 1.2),
      ParlayLeg.fromMatch(match, 'Draw', 3.0),
    ]));
    expect(c.legs.first.verdict, 'Below market');
    expect(c.summary.any((s) => s.startsWith('Two picks from Everton vs Chelsea')), isTrue);
  });

  test('risk grows with legs and odds', () async {
    const short = ParlayLeg(selection: 'Pick', odds: 1.4), even = ParlayLeg(selection: 'Pick', odds: 1.9);
    expect((await checker.check(parlay([short, short, short]))).risk, 'Low');
    expect((await checker.check(parlay([short, short, short, short]))).risk, 'Medium');
    expect((await checker.check(parlay([even, even, even, even]))).risk, 'High');
  });
}
