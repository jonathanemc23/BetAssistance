import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/live_alert_service.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/logic/live_alerts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final kickoff = DateTime.utc(2026, 10, 20, 19);
const league = League('eng.1', 'Premier League');

Match match(MatchState state, {String? h, String? a, String detail = '', String id = '701'}) => Match(
      id: id,
      league: league,
      kickoff: kickoff,
      home: Team('Arsenal', 'ARS', null, h),
      away: Team('Chelsea', 'CHE', null, a),
      state: state,
      detail: detail,
    );

Bet bet({BetStatus status = BetStatus.pending, String id = '701'}) =>
    match(MatchState.scheduled, id: id).toBetTemplate(selection: 'Arsenal to win', odds: 2.1).copyWith(status: status, stake: 10);

class ListSink implements AlertSink {
  final shown = <LiveAlert>[];
  var asked = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  Future<void> show(LiveAlert alert) async => shown.add(alert);
}

void main() {
  final w = WatchedMatch(match(MatchState.scheduled), 'Soccer', const ['Arsenal to win']);

  group('alertFor', () {
    test('kick-off, goal, correction and full time', () {
      final pre = MatchSnapshot.of(match(MatchState.scheduled));
      final ko = alertFor(w, pre, match(MatchState.live, h: '0', a: '0', detail: "1'"))!;
      expect(ko.kind, AlertKind.kickoff);
      expect(ko.title, 'Kick-off: Arsenal vs Chelsea');
      expect(ko.body, contains('Your pick: Arsenal to win'));

      final live = MatchSnapshot.of(match(MatchState.live, h: '0', a: '0'));
      expect(alertFor(w, live, match(MatchState.live, h: '0', a: '0', detail: "12'")), isNull);
      final goal = alertFor(w, live, match(MatchState.live, h: '1', a: '0', detail: "23'"))!;
      expect(goal.title, 'Goal! Arsenal 1-0 Chelsea');
      expect(goal.body, startsWith("23'"));

      final one = MatchSnapshot.of(match(MatchState.live, h: '1', a: '0'));
      expect(alertFor(w, one, match(MatchState.live, h: '0', a: '0'))!.title, 'Score corrected: Arsenal 0-0 Chelsea');

      final ft = alertFor(w, one, match(MatchState.finished, h: '2', a: '1', detail: 'FT'))!;
      expect(ft.kind, AlertKind.finalResult);
      expect(ft.title, 'Full time: Arsenal 2-1 Chelsea');
      expect(alertFor(w, MatchSnapshot.of(match(MatchState.finished, h: '2', a: '1')),
          match(MatchState.finished, h: '2', a: '1')), isNull);
    });

    test('a first reading of a live match is only recorded', () {
      expect(alertFor(w, null, match(MatchState.live, h: '1', a: '0')), isNull);
      expect(alertFor(w, null, match(MatchState.finished, h: '1', a: '0'))!.kind, AlertKind.finalResult);
    });

    test('a kick-off missed between polls reports the score', () {
      final pre = MatchSnapshot.of(match(MatchState.scheduled));
      expect(alertFor(w, pre, match(MatchState.live, h: '1', a: '0'))!.title, 'Under way: Arsenal 1-0 Chelsea');
    });

    test('other sports say score update', () {
      final b = WatchedMatch(match(MatchState.scheduled, id: '9'), 'Basketball', const []);
      final last = MatchSnapshot.of(match(MatchState.live, h: '10', a: '8', id: '9'));
      final a = alertFor(b, last, match(MatchState.live, h: '12', a: '8', id: '9'))!;
      expect(a.title, startsWith('Score update:'));
    });
  });

  group('watchedMatches', () {
    test('pending bets and open parlay legs near kick-off, once per match', () {
      final parlay = Parlay(
        name: 'Parlay 1',
        legs: [ParlayLeg.fromMatch(match(MatchState.scheduled), 'Over 2.5', 1.9)],
        created: '',
        updated: '',
      );
      final at = kickoff.subtract(const Duration(minutes: 10));
      final ws = watchedMatches([bet(), bet(status: BetStatus.won, id: '702')], [parlay], at);
      expect(ws, hasLength(1));
      expect(ws.single.picks, ['Arsenal to win', 'Parlay 1: Over 2.5']);
      expect(ws.single.match.home.name, 'Arsenal');

      expect(watchedMatches([bet()], const [], kickoff.subtract(const Duration(hours: 2))), isEmpty);
      expect(watchedMatches([bet()], const [], kickoff.add(const Duration(hours: 5))), isEmpty);
      // Still live in the last reading: keep following a long game.
      expect(
          watchedMatches([bet()], const [], kickoff.add(const Duration(hours: 5)),
              seen: {'701': MatchSnapshot.of(match(MatchState.live, h: '0', a: '0'))}),
          hasLength(1));
      expect(
          watchedMatches([bet()], const [], kickoff.add(const Duration(hours: 1)),
              seen: {'701': MatchSnapshot.of(match(MatchState.finished, h: '0', a: '0'))}),
          isEmpty);
    });
  });

  test('snapshots survive a restart and old ones are dropped', () {
    final all = {
      '701': MatchSnapshot.of(match(MatchState.live, h: '1', a: '0')),
      'old': MatchSnapshot(MatchState.finished, '0', '0', kickoff.subtract(const Duration(days: 3))),
    };
    final back = MatchSnapshot.decodeAll(MatchSnapshot.encodeAll(all, kickoff));
    expect(back.keys, ['701']);
    expect(back['701']!.state, MatchState.live);
    expect(back['701']!.home, '1');
    expect(MatchSnapshot.decodeAll('not json'), isEmpty);
  });

  group('LiveAlertService', () {
    sqfliteFfiInit();
    late BankStore store;
    setUp(() async {
      store = BankStore(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      await store.saveBet(bet());
    });

    test('follows a match from kick-off to full time', () async {
      var now = kickoff.subtract(const Duration(minutes: 5));
      var feed = match(MatchState.scheduled);
      final sink = ListSink();
      final service = LiveAlertService(
        store: store,
        api: FixturesApi(),
        sink: sink,
        clock: () => now,
        read: (ms) async => {for (final m in ms) m.id: feed},
      );
      Future<List<String>> step(Match m, Duration later) async {
        feed = m;
        now = now.add(later);
        return [for (final a in await service.poll()) a.title];
      }

      expect(await step(match(MatchState.scheduled), Duration.zero), isEmpty);
      expect(sink.asked, 1);
      expect(await step(match(MatchState.live, h: '0', a: '0'), const Duration(minutes: 6)),
          ['Kick-off: Arsenal vs Chelsea']);
      expect(await step(match(MatchState.live, h: '0', a: '0'), const Duration(minutes: 1)), isEmpty);
      expect(await step(match(MatchState.live, h: '0', a: '1'), const Duration(minutes: 30)),
          ['Goal! Arsenal 0-1 Chelsea']);
      expect(await step(match(MatchState.finished, h: '0', a: '1'), const Duration(minutes: 70)),
          ['Full time: Arsenal 0-1 Chelsea']);
      expect(await step(match(MatchState.finished, h: '0', a: '1'), const Duration(minutes: 1)), isEmpty);
      expect(sink.shown, hasLength(3));
      expect(sink.asked, 1);
    });

    test('turned off in settings: no requests, no alerts', () async {
      await store.setPref(alertsEnabledPref, '0');
      var reads = 0;
      final service = LiveAlertService(
        store: store,
        api: FixturesApi(),
        sink: ListSink(),
        clock: () => kickoff,
        read: (ms) async {
          reads++;
          return {};
        },
      );
      expect(await service.poll(), isEmpty);
      expect(reads, 0);
    });
  });
}
