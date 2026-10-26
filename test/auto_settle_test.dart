import 'dart:io';
import 'dart:math' as math;

import 'package:bank_track/data/bet_settler.dart';
import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/live_alert_service.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/logic/auto_settle.dart';
import 'package:bank_track/logic/community.dart';
import 'package:bank_track/logic/live_alerts.dart';
import 'package:bank_track/logic/nba_stake.dart';
import 'package:bank_track/logic/pro_tips.dart';
import 'package:bank_track/ui/stake_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'live_alerts_test.dart' show ListSink;

final kickoff = DateTime.utc(2026, 10, 20, 19);
const league = League('eng.1', 'Premier League');

Match match(MatchState state, {String id = '701', String? h, String? a, String home = 'Arsenal', String away = 'Chelsea'}) =>
    Match(
      id: id,
      league: league,
      kickoff: kickoff,
      home: Team(home, home, null, h),
      away: Team(away, away, null, a),
      state: state,
      detail: '',
    );

Bet single(String selection, {String id = '701', String? market}) => match(MatchState.scheduled, id: id)
    .toBetTemplate(selection: selection, odds: 2, market: market)
    .copyWith(stake: 10);

NbaGame game(String id, int hour, {bool scheduled = true}) => NbaGame(
      id: id,
      home: 'Home $id',
      away: 'Away $id',
      tipoff: DateTime.utc(2026, 10, 27, hour),
      scheduled: scheduled,
      leaders: [
        NbaLeader('a$id', 'Scorer $id', 'Home $id', PropStat.points, 24.5),
        NbaLeader('b$id', 'Big $id', 'Home $id', PropStat.rebounds, 10.2),
        NbaLeader('c$id', 'Guard $id', 'Away $id', PropStat.assists, 8.1),
      ],
    );

void main() {
  sqfliteFfiInit();
  widgetTests();

  group('grading', () {
    test('from the final score, only once the match is over', () {
      final ft = match(MatchState.finished, h: '2', a: '1');
      expect(gradeOnScore('result', 'Arsenal to win', ft), BetStatus.won);
      expect(gradeOnScore('goals', 'Under 2.5 goals', ft), BetStatus.lost);
      expect(gradeOnScore('dnb', 'Chelsea draw no bet', match(MatchState.finished, h: '1', a: '1')), BetStatus.push);
      expect(gradeOnScore('corners', 'Over 9.5 corners', ft), isNull);
      expect(gradeOnScore('result', 'Arsenal to win', match(MatchState.live, h: '2', a: '1')), isNull);
      expect(dueForResult(kickoff, kickoff.add(const Duration(minutes: 30))), isFalse);
      expect(dueForResult(kickoff, kickoff.add(const Duration(hours: 3))), isTrue);
      expect(dueForResult(kickoff, kickoff.add(const Duration(days: 11))), isFalse);
    });

    test('player lines from a box score', () {
      expect(parsePropPick('20+ points: Kevin Durant'), (PropStat.points, 20, 'Kevin Durant'));
      expect(parsePropPick('Rui Hachimura 2+ threes'), (PropStat.threes, 2, 'Rui Hachimura'));
      expect(parsePropPick('Arsenal to win'), isNull);

      final box = parseNbaBoxScore(File('test/data/espn_nba_summary.json').readAsStringSync());
      expect(box.finished, isTrue);
      expect(box.stat('Luka Doncic', PropStat.points), 52);
      expect(gradeProp(PropStat.points, 30, 'Luka Doncic', box), BetStatus.won);
      expect(gradeProp(PropStat.points, 30, 'Austin Reaves', box), BetStatus.lost);
      expect(gradeProp(PropStat.points, 10, 'Bronny James', box), BetStatus.voided); // didn't play
    });
  });

  group('pro tips', () {
    test("today's scoreboard gives the games and each team's leaders", () {
      final games = parseNbaScoreboard(File('test/data/espn_nba_scoreboard.json').readAsStringSync());
      expect(games, hasLength(2));
      expect(games.first.title, 'Charlotte Hornets vs Washington Wizards');
      expect(games.first.scheduled, isTrue);
      expect(games.first.leaders.map((l) => l.stat).toSet(), {PropStat.points, PropStat.rebounds, PropStat.assists});
      expect(games.first.leaders.firstWhere((l) => l.stat == PropStat.points).name, 'Naz Reid');
    });

    test('2 or 3 lines on different players, total odds 2.40 to 3.70', () {
      final now = DateTime.utc(2026, 10, 27, 12);
      final games = [game('1', 23), game('2', 23), game('3', 26), game('4', 10)];
      final sizes = <int>{};
      for (var seed = 0; seed < 300; seed++) {
        final s = generateProStake(games, now, math.Random(seed))!;
        sizes.add(s.legs.length);
        expect(s.legs.length, inInclusiveRange(2, 3));
        expect(s.odds, inInclusiveRange(proStakeMinOdds, proStakeMaxOdds), reason: 'seed $seed');
        expect(s.legs.map((l) => l.player).toSet(), hasLength(s.legs.length));
        // Different games when there are enough, never one that started.
        expect(s.legs.map((l) => l.gameId).toSet(), hasLength(s.legs.length));
        expect(s.legs.any((l) => l.gameId == '4'), isFalse);
        for (final l in s.legs) {
          expect(l.line, greaterThanOrEqualTo(l.stat.minLine));
          expect(l.odds, greaterThan(1.2));
        }
        expect(s.cost, 6);
      }
      expect(sizes, {2, 3});
    });

    test('none when no NBA game is left to start today', () {
      final now = DateTime.utc(2026, 10, 27, 12);
      expect(generateProStake(const [], now, math.Random(1)), isNull);
      expect(generateProStake([game('4', 10), game('5', 20, scheduled: false)], now, math.Random(1)), isNull);
    });

    test('a pro tip logs as a parlay with its legs tied to their games', () {
      final s = generateProStake([game('1', 23), game('2', 23)], DateTime.utc(2026, 10, 27, 12), math.Random(3))!;
      final b = s.toBet(stake: 20);
      expect(b.isParlay, isTrue);
      expect(b.legs.every((l) => l.isLinked && l.leagueSlug == 'nba'), isTrue);
      expect(parsePropPick(b.legs.first.selection), isNotNull);
      expect(ProStake.fromJson(s.toJson())!.legs.first.label, s.legs.first.label);
    });
  });

  group('BetSettler', () {
    late BankStore store;
    late Map<String, Match> feed;
    late Map<String, NbaBoxScore> boxes;
    late BetSettler settler;
    var now = kickoff.add(const Duration(hours: 3));

    setUp(() async {
      store = BankStore(await AppDatabase.open(
          factory: databaseFactoryFfi, path: '${Directory.systemTemp.createTempSync('settle').path}/bank.db'));
      await store.load();
      feed = {};
      boxes = {};
      now = kickoff.add(const Duration(hours: 3));
      settler = BetSettler(
        store: store,
        api: FixturesApi(),
        clock: () => now,
        read: (ms) async => {for (final m in ms) m.id: ?feed[m.id]},
        box: (id) async => boxes[id],
      );
    });

    test('puts in the result of singles once their match is over', () async {
      await store.saveBet(single('Arsenal to win'));
      await store.saveBet(single('Over 9.5 corners', market: 'corners'));
      await store.saveBet(single('Chelsea to win', id: '702'));
      await store.saveBet(const Bet(selection: 'Typed by hand', date: '2026-10-20', stake: 5, odds: 2, created: 'x'));

      feed['701'] = match(MatchState.live, h: '1', a: '0');
      feed['702'] = match(MatchState.scheduled, id: '702');
      expect(await settler.run(), isEmpty);
      expect(store.bets.where((b) => b.status == BetStatus.pending), hasLength(4));

      feed['701'] = match(MatchState.finished, h: '2', a: '1');
      final alerts = await settler.run();
      expect(alerts.single.kind, AlertKind.settled);
      expect(alerts.single.title, 'Bet won: Arsenal to win');
      expect(alerts.single.body, startsWith('Arsenal 2-1 Chelsea'));
      String status(String sel) => store.bets.firstWhere((b) => b.selection == sel).status.name;
      expect(status('Arsenal to win'), 'won');
      expect(status('Over 9.5 corners'), 'pending'); // not from the score
      expect(status('Chelsea to win'), 'pending');
      expect(status('Typed by hand'), 'pending');
      expect(await settler.run(), isEmpty); // nothing new
    });

    test('settles parlay legs one by one and the parlay with the last', () async {
      BetLeg leg(String id, String sel) {
        final m = match(MatchState.scheduled, id: id, home: 'Home $id', away: 'Away $id');
        return BetLeg(selection: sel, event: m.title, sport: 'Soccer', odds: 1.8, matchId: id, leagueSlug: 'eng.1', kickoff: kickoff);
      }

      await store.saveBet(Bet(
        type: BetType.parlay,
        selection: '2-leg parlay',
        date: '2026-10-20',
        stake: 10,
        odds: 3.24,
        created: 'p',
        legs: [leg('801', 'Home 801 to win'), leg('802', 'Over 2.5 goals')],
      ));
      // The links survive the database.
      expect(store.bets.single.legs.every((l) => l.isLinked), isTrue);

      feed['801'] = match(MatchState.finished, id: '801', h: '1', a: '0', home: 'Home 801', away: 'Away 801');
      feed['802'] = match(MatchState.live, id: '802', h: '1', a: '1', home: 'Home 802', away: 'Away 802');
      expect(await settler.run(), isEmpty);
      expect(store.bets.single.status, BetStatus.pending);
      expect(store.bets.single.legs.first.status, BetStatus.won);

      feed['802'] = match(MatchState.finished, id: '802', h: '2', a: '1', home: 'Home 802', away: 'Away 802');
      final alerts = await settler.run();
      expect(store.bets.single.status, BetStatus.won);
      expect(alerts.single.title, 'Bet won: 2-leg parlay');
    });

    test('settles Parlay builder legs, community bets and pro tips', () async {
      await store.newParlay(legs: [ParlayLeg.fromMatch(match(MatchState.scheduled), 'Arsenal to win', 1.9)]);
      final cb = CommunityBet.on(match(MatchState.scheduled), const TipLeg(TipMarket.awayWin, 'Chelsea to win', 2.1),
          placed: '2026-10-19T10:00:00');
      await store.buyListing(Listing(seller: demoSellers.first, bet: cb, price: 1));
      final stake = ProStake(id: 'pro:1', created: kickoff, legs: [
        NbaProp(
            gameId: '401909861', home: 'Utah Jazz', away: 'Los Angeles Lakers', tipoff: kickoff, player: 'Luka Doncic',
            team: 'LAL', stat: PropStat.points, line: 30, odds: 1.7),
        NbaProp(
            gameId: '401909861', home: 'Utah Jazz', away: 'Los Angeles Lakers', tipoff: kickoff, player: 'Lauri Markkanen',
            team: 'UTA', stat: PropStat.rebounds, line: 20, odds: 1.8),
      ]);
      await store.addTokens(10);
      expect(await store.buyProStake(stake), isTrue);

      feed['701'] = match(MatchState.finished, h: '2', a: '1');
      feed['401909861'] = Match(
        id: '401909861',
        league: leagueBySlug('nba')!,
        kickoff: kickoff,
        home: const Team('Utah Jazz', 'UTA', null, '120'),
        away: const Team('Los Angeles Lakers', 'LAL', null, '128'),
        state: MatchState.finished,
        detail: 'Final',
      );
      boxes['401909861'] = parseNbaBoxScore(File('test/data/espn_nba_summary.json').readAsStringSync());
      await settler.run();

      expect(store.parlays.single.status, BetStatus.won);
      expect(store.boughtListings.values.single.bet.result, 'lost');
      final s = store.proStakes.single;
      expect(s.legs.map((l) => l.status), [BetStatus.won, BetStatus.lost]);
      expect(s.status, BetStatus.lost);
    });

    test('the alert service settles and notifies, and settles with alerts off', () async {
      await store.saveBet(single('Arsenal to win'));
      feed['701'] = match(MatchState.finished, h: '0', a: '1');
      final sink = ListSink();
      final service = LiveAlertService(
          store: store, api: FixturesApi(), sink: sink, settler: settler, read: (_) async => const {}, clock: () => now);
      await service.poll();
      expect(store.bets.single.status, BetStatus.lost);
      expect(sink.shown.single.title, 'Bet lost: Arsenal to win');

      await store.setPref(alertsEnabledPref, '0');
      await store.saveBet(single('Chelsea to win', id: '702'));
      feed['702'] = match(MatchState.finished, id: '702', h: '0', a: '1');
      now = now.add(const Duration(minutes: 11));
      await service.poll();
      expect(store.bets.firstWhere((b) => b.selection == 'Chelsea to win').status, BetStatus.won);
      expect(sink.shown, hasLength(1));
    });
  });
}

/// The NBA scoreboard fixture for any day, or an empty day.
FixturesApi nbaApi({bool games = true}) => FixturesApi(
      client: MockClient((req) async {
        if (req.url.path.endsWith('/basketball/nba/scoreboard')) {
          return http.Response(
              games ? File('test/data/espn_nba_scoreboard.json').readAsStringSync() : '{"events":[]}', 200);
        }
        return http.Response('{}', 404);
      }),
    );

Future<void> pumpBuilder(WidgetTester tester, BankStore store, FixturesApi api) async {
  await tester.pumpWidget(MaterialApp(
    home: StakeBuilderPage(store: store, api: api, today: DateTime.utc(2026, 10, 26, 12)),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

void widgetTests() {
  testWidgets('Stake builder: no NBA games today says so and takes no tokens', (tester) async {
    final store = (await tester.runAsync(() async {
      final s = BankStore(await AppDatabase.open(
          factory: databaseFactoryFfi, path: '${Directory.systemTemp.createTempSync('w').path}/bank.db'));
      await s.load();
      return s;
    }))!;
    await pumpBuilder(tester, store, nbaApi(games: false));
    expect(find.text('No NBA matches today, try again tomorrow'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('pro-stake-none'))).onPressed, isNull);
    expect(store.tokens, BankStore.starterTokens);
  });

  testWidgets('Stake builder: generate an NBA pro tip for 6 tokens', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(() async {
      final s = BankStore(await AppDatabase.open(
          factory: databaseFactoryFfi, path: '${Directory.systemTemp.createTempSync('w').path}/bank.db'));
      await s.load();
      return s;
    }))!;
    await pumpBuilder(tester, store, nbaApi());
    expect(find.text('Generate pro tip · 6 tokens'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pro-stake-generate')));
    await tester.pumpAndSettle();
    expect(find.text('Generate an NBA pro tip?'), findsOneWidget);
    await tester.tap(find.text('Generate'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(store.tokens, BankStore.starterTokens - 6);
    final s = store.proStakes.single;
    expect(s.odds, inInclusiveRange(2.4, 3.7));
    expect(find.byKey(Key('pro-stake-${s.id}')), findsOneWidget);
    expect(find.text('${s.legs.first.label} - Yes'), findsOneWidget);
    expect(find.textContaining('of ${s.legs.length} finished'), findsOneWidget);
  });
}
