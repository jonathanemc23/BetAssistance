import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/bet_review.dart';
import 'package:bank_track/logic/stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // Everton vs Chelsea before kick-off; anything else the finished
  // Medellín 0-1 Santa Fe match.
  final api = FixturesApi(
    client: MockClient(
      (req) async => http.Response.bytes(
        File(
          req.url.queryParameters['event'] == '401878771'
              ? 'test/data/espn_summary_pre.json'
              : 'test/data/espn_summary_col.json',
        ).readAsBytesSync(),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );
  final reviewer = DataBetReviewer(api, now: () => DateTime.utc(2026, 10, 17, 12));
  const settings = Settings(startBankroll: 1000, startDate: '2026-01-01', unit: 10);

  Bet linked(String id, String slug, String event, String selection, double odds, {double stake = 10}) => Bet(
    selection: selection,
    event: event,
    sport: 'Soccer',
    date: '2026-10-06',
    stake: stake,
    odds: odds,
    created: '2026-10-01T10:00:00',
    matchId: id,
    leagueSlug: slug,
    leagueName: 'League',
    kickoff: DateTime.utc(2026, 10, 18, 19),
  );

  Future<BetReview> review(Bet b, [List<Bet> history = const []]) =>
      reviewer.review(b, history: history, stats: Stats.compute(settings, history, const []), settings: settings);

  test('a finished match grades the pick and suggests the result', () async {
    final b = linked(
      '401877960',
      'col.1',
      'Independiente Medellín vs Independiente Santa Fe',
      'Independiente Santa Fe to win',
      2.6,
    );
    final r = await review(b);
    expect(r.suggestedResult, BetStatus.won);
    expect(r.headline, 'Match over: this pick looks won.');
    final updates = r.sections.firstWhere((s) => s.kind == 'updates').lines;
    expect(updates.first, 'Full time: Independiente Medellín 0-1 Independiente Santa Fe.');
    expect(r.sections.firstWhere((s) => s.kind == 'suggestions').lines.first, contains('Mark the bet as won'));
  });

  test('a pick before kick-off gets a price check, context, staking advice and the record', () async {
    final history = [
      Bet(
        selection: 'Arsenal to win',
        sport: 'Soccer',
        date: '2026-09-01',
        stake: 10,
        odds: 2.0,
        status: BetStatus.won,
        created: 'x',
        id: 1,
      ),
      Bet(
        selection: 'Spurs to win',
        sport: 'Soccer',
        date: '2026-09-02',
        stake: 10,
        odds: 2.0,
        status: BetStatus.lost,
        created: 'x',
        id: 2,
      ),
    ];
    final b = linked('401878771', 'eng.1', 'Everton vs Chelsea', 'Chelsea to win', 3.0, stake: 60);
    final r = await review(b, history);
    final kinds = r.sections.map((s) => s.kind).toList();
    expect(kinds, containsAllInOrder(['bet', 'updates', 'market', 'context', 'suggestions', 'record']));
    final market = r.sections.firstWhere((s) => s.kind == 'market');
    expect(market.tone, ReviewTone.good);
    expect(market.lines.first, startsWith('Best price now'));
    final tips = r.sections.firstWhere((s) => s.kind == 'suggestions').lines;
    expect(tips.any((t) => t.startsWith('This stake is 6.0 units')), isTrue);
    expect(tips.any((t) => t.startsWith('Long shot')), isTrue);
    final record = r.sections.firstWhere((s) => s.kind == 'record').lines;
    expect(record.first, 'Match result: 2 settled, 1 won, 1 lost, ROI +0%.');
  });

  test('a bet with no match still gets a review', () async {
    const b = Bet(selection: 'Underdog by KO', sport: 'MMA', date: '2026-10-01', stake: 10, odds: 3.4, created: 'x');
    final r = await review(b);
    expect(r.match, isNull);
    expect(r.sections.first.kind, 'bet');
    expect(r.sections.any((s) => s.kind == 'suggestions'), isTrue);
  });
}
