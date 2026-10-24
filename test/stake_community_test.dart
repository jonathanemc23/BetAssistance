import 'dart:convert';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/logic/community.dart';
import 'package:bank_track/logic/pro_tips.dart';
import 'package:bank_track/logic/stake_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finished game's summary as ESPN sends it, with a few box score stats.
String boxSummary({
  required String homeId,
  required String awayId,
  required int hs,
  required int as,
  Map<String, (int, int)> stats = const {},
  String state = 'post',
}) =>
    jsonEncode({
      'header': {
        'competitions': [
          {
            'status': {'type': {'state': state}},
            'competitors': [
              {'homeAway': 'home', 'team': {'id': homeId, 'displayName': 'Team $homeId'}, 'score': '$hs'},
              {'homeAway': 'away', 'team': {'id': awayId, 'displayName': 'Team $awayId'}, 'score': '$as'},
            ],
          },
        ],
      },
      'boxscore': {
        'teams': [
          for (final side in ['home', 'away'])
            {
              'homeAway': side,
              'statistics': [
                for (final e in stats.entries)
                  {'name': e.key, 'label': e.key, 'displayValue': '${side == 'home' ? e.value.$1 : e.value.$2}'},
              ],
            },
        ],
      },
    });

Match match({String id = '77', DateTime? kickoff}) => Match(
      id: id,
      league: League('eng.1', 'Premier League'),
      kickoff: kickoff ?? DateTime.utc(2030, 1, 1, 15),
      home: const Team('Everton', 'Everton', null, null),
      away: const Team('Chelsea', 'Chelsea', null, null),
      state: MatchState.scheduled,
      detail: '',
    );

void main() {
  group('stake stats', () {
    test('a game counts from the team\'s side: corners and cards both ways', () {
      final d = parseMatchDetails(boxSummary(homeId: '1', awayId: '2', hs: 2, as: 1, stats: {
        'wonCorners': (7, 3),
        'yellowCards': (2, 4),
        'redCards': (0, 1),
      }));
      final away = statGameOf(d, '2')!;
      expect(away.atHome, isFalse);
      expect(away.score, '1-2');
      expect(away.own(StakeStat.corners), 3);
      expect(away.allowed(StakeStat.corners), 7);
      expect(away.own(StakeStat.cards), 5);
      expect(away.total(StakeStat.goals), 3);
      expect(statGameOf(d, '9'), isNull);
    });

    StatGame g(int gf, int ga, int cf, int ca) => StatGame(
          date: null,
          opponent: 'X',
          atHome: true,
          goalsFor: gf,
          goalsAgainst: ga,
          mine: {StakeStat.corners: cf},
          theirs: {StakeStat.corners: ca},
        );
    final stats = StakeStats(
      home: TeamForm(team: 'Everton', games: [g(2, 1, 6, 4), g(1, 1, 5, 5), g(3, 0, 8, 2), g(0, 2, 4, 6)]),
      away: TeamForm(team: 'Chelsea', games: [g(2, 2, 7, 3), g(1, 0, 6, 4), g(2, 1, 5, 5), g(4, 1, 9, 3)]),
    );

    test('averages, expected numbers, lines and hit rates', () {
      expect(stats.home.avgFor(StakeStat.goals), 1.5);
      expect(stats.away.avgTotal(StakeStat.corners), 10.5);
      // Everton make 5.75 and Chelsea allow 3.75: 4.75 expected for Everton.
      expect(stats.expected(StakeStat.corners, StakeScope.home), closeTo(4.75, 1e-9));
      expect(stats.expected(StakeStat.corners, StakeScope.match), closeTo(10.25, 1e-9));
      expect(stats.lines(StakeStat.corners, StakeScope.match), [9.5, 10.5, 11.5]);
      // Totals 10,10,10,10 and 10,10,10,12: 8 games, 1 over 10.5.
      expect(stats.hitRate(StakeStat.corners, StakeScope.match, over: true, line: 10.5), 1 / 8);
      expect(stats.hitRate(StakeStat.corners, StakeScope.match, over: true, line: 9.5), 1);
    });

    test('a pick keeps its slot, label and saved form', () {
      final p = StakePick.of(match(), stats, StakeStat.corners, StakeScope.match, over: true, line: 9.5);
      expect(p.label, 'Over 9.5 corners');
      expect(p.hitRate, 1);
      final back = StakePick.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.slot, p.slot);
      expect(back.line, 9.5);
      expect(StakePick.of(match(), stats, StakeStat.goals, StakeScope.away, over: false, line: 1.5).label,
          'Chelsea under 1.5 goals');
    });

    test('validation before kick-off goes by the hit rate and the average', () {
      final strong = StakePick.of(match(), stats, StakeStat.corners, StakeScope.match, over: true, line: 9.5);
      expect(checkPick(strong, stats: stats).verdict, PickVerdict.strong);
      final weak = StakePick.of(match(), stats, StakeStat.corners, StakeScope.match, over: true, line: 10.5);
      expect(checkPick(weak, stats: stats).verdict, PickVerdict.risky);
      // Without fresh stats, the rate saved with the pick.
      expect(checkPick(strong).verdict, PickVerdict.strong);
      final review = StakeReview([checkPick(strong, stats: stats), checkPick(weak, stats: stats)]);
      expect(review.chance, closeTo(1 / 8, 1e-9));
      expect(review.summary, contains('1 pick looks weak'));
    });

    test('validation once the match is on goes by the match\'s stats', () {
      final over = StakePick.of(match(), stats, StakeStat.corners, StakeScope.match, over: true, line: 9.5);
      final under = StakePick.of(match(), stats, StakeStat.corners, StakeScope.home, over: false, line: 4.5);
      final live = parseMatchDetails(boxSummary(homeId: '1', awayId: '2', hs: 0, as: 0, state: 'in', stats: {'wonCorners': (3, 4)}));
      expect(checkPick(over, result: live).verdict, PickVerdict.behind);
      expect(checkPick(under, result: live).verdict, PickVerdict.onTrack);
      final done = parseMatchDetails(boxSummary(homeId: '1', awayId: '2', hs: 1, as: 1, stats: {'wonCorners': (6, 5)}));
      expect(checkPick(over, result: done).verdict, PickVerdict.won);
      expect(checkPick(over, result: done).actual, 11);
      expect(checkPick(under, result: done).verdict, PickVerdict.lost);
      expect(StakeReview([checkPick(under, result: done)]).summary, contains('lost'));
    });
  });

  group('pro bettor challenge', () {
    final now = DateTime(2030, 1, 1, 12);
    CommunityBet bet(int i, {double odds = 1.8}) => CommunityBet.on(
          match(id: 'm$i', kickoff: DateTime.utc(2030, 1, 2)),
          TipLeg(TipMarket.homeWin, 'Everton to win', odds),
          placed: '$i',
        );

    ProChallenge play(int won, int lost) {
      var c = const ProChallenge().accept(now);
      for (var i = 0; i < won + lost; i++) {
        c = c.place(bet(i));
      }
      for (var i = 0; i < won + lost; i++) {
        c = c.settle('m$i', i < won ? 2 : 0, i < won ? 0 : 1, now);
      }
      return c;
    }

    test('only an accepted challenge takes bets, at 1.40 or more, before kick-off', () {
      expect(const ProChallenge().refuse(bet(1), now), isNotNull);
      final c = const ProChallenge().accept(now);
      expect(c.status(now), ChallengeStatus.active);
      expect(c.refuse(bet(1), now), isNull);
      expect(c.refuse(bet(1, odds: 1.3), now), contains('1.40'));
      expect(c.refuse(bet(1), DateTime.utc(2030, 1, 3)), isNotNull);
      expect(c.place(bet(1)).refuse(bet(1), now), isNotNull);
    });

    test('18 of 30 won passes; 17 means a week\'s wait', () {
      final pass = play(18, 12);
      expect(pass.status(now), ChallengeStatus.passed);
      final fail = play(17, 13);
      expect(fail.status(now), ChallengeStatus.waiting);
      expect(fail.lastRate, closeTo(17 / 30, 1e-9));
      expect(fail.waitUntil, now.add(const Duration(days: 7)));
      expect(fail.status(now.add(const Duration(days: 8))), ChallengeStatus.notStarted);
      expect(fail.accept(now.add(const Duration(days: 8))).status(now.add(const Duration(days: 8))), ChallengeStatus.active);
    });

    test('30 placed and not all settled waits for the results', () {
      var c = const ProChallenge().accept(now);
      for (var i = 0; i < 30; i++) {
        c = c.place(bet(i));
      }
      expect(c.status(now), ChallengeStatus.awaitingResults);
      expect(c.refuse(bet(40), now), isNotNull);
    });

    test('the restart shows after 10 bets and costs a week', () {
      var c = const ProChallenge().accept(now);
      for (var i = 0; i < 9; i++) {
        c = c.place(bet(i));
      }
      expect(c.canRestart(now), isFalse);
      c = c.place(bet(9));
      expect(c.canRestart(now), isTrue);
      final r = c.restart(now);
      expect(r.status(now), ChallengeStatus.waiting);
      expect(r.bets, isEmpty);
      expect(r.status(now.add(const Duration(days: 7, minutes: 1))), ChallengeStatus.notStarted);
    });

    test('the challenge and its bets survive a restart of the app', () {
      final c = play(3, 1);
      final back = ProChallenge.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.placed, 4);
      expect(back.wins, 3);
      expect(back.status(now), ChallengeStatus.active);
    });
  });

  group('community', () {
    test('handles are 3 to 20 lower case letters, digits or _', () {
      expect(cleanHandle('@Laura_Bets'), 'laura_bets');
      expect(cleanHandle('ab'), isNull);
      expect(cleanHandle('no spaces'), isNull);
    });

    test('bets for sale are the same on every visit and priced by their odds', () {
      final m = Match(
        id: '401878771',
        league: League('eng.1', 'Premier League'),
        kickoff: DateTime.utc(2030, 1, 1),
        home: const Team('Everton', 'Everton', null, null),
        away: const Team('Chelsea', 'Chelsea', null, null),
        state: MatchState.scheduled,
        detail: '',
      );
      final a = demoListings([m], day: '2030-01-01'), b = demoListings([m], day: '2030-01-01');
      expect(a, hasLength(1));
      expect(a.single.id, b.single.id);
      expect(a.single.bet.leg.odds, inInclusiveRange(1.5, 2.6));
      expect(a.single.price, listingPrice(a.single.bet.leg.odds));
      expect(Listing.fromJson(jsonDecode(jsonEncode(a.single.toJson())))!.seller.handle, a.single.seller.handle);
    });
  });
}
