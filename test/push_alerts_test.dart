import 'dart:convert';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/live_alert_service.dart';
import 'package:bank_track/data/push_alerts.dart';
import 'package:bank_track/data/push_channel.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/logic/live_alerts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'live_alerts_test.dart' show bet, kickoff, match, ListSink;

class FakeChannel implements PushChannel {
  bool allowed = true;
  bool subscribed = false;
  @override
  bool get supported => true;
  @override
  bool get permitted => allowed;
  @override
  Future<void> register() async {}
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<Map<String, dynamic>?> subscribe(String serverKey) async {
    subscribed = true;
    return {
      'endpoint': 'https://web.push.apple.com/abc',
      'keys': {'p256dh': 'BNc', 'auth': 'tBH'},
    };
  }

  @override
  Future<Map<String, dynamic>?> current() async => subscribed ? await subscribe('') : null;
  @override
  Future<String?> unsubscribe() async {
    subscribed = false;
    return 'https://web.push.apple.com/abc';
  }
}

void main() {
  sqfliteFfiInit();
  late BankStore store;
  late List<http.Request> requests;
  late FakeChannel channel;
  var now = kickoff.subtract(const Duration(days: 1));

  PushAlerts push() => PushAlerts(
        server: 'https://alerts.example.com/',
        channel: channel,
        clock: () => now,
        client: MockClient((req) async {
          requests.add(req);
          if (req.url.path == '/push/key') return http.Response('{"key":"BHfw"}', 200);
          return http.Response('', 204);
        }),
      );

  setUp(() async {
    store = BankStore(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    await store.saveBet(bet());
    requests = [];
    channel = FakeChannel();
    now = kickoff.subtract(const Duration(days: 1));
  });

  test('the server is told about matches with open bets in the coming week', () {
    final ms = pushMatches(store.bets, store.parlays, now);
    expect(ms, [
      {
        'id': '701',
        'feed': 'soccer/eng.1',
        'sport': 'Soccer',
        'kickoff': '2026-10-20T19:00:00.000Z',
        'home': 'Arsenal',
        'away': 'Chelsea',
        'picks': ['Arsenal to win'],
      },
    ]);
    expect(pushMatches(store.bets, store.parlays, kickoff.subtract(const Duration(days: 8))), isEmpty);
  });

  test('switching alerts on subscribes and sends the list, then only when it changes', () async {
    final p = push();
    await p.prepare(store);
    expect(await p.enable(store), isTrue);
    final put = requests.singleWhere((r) => r.method == 'PUT');
    expect(put.url.toString(), 'https://alerts.example.com/push/devices');
    final body = jsonDecode(put.body) as Map<String, dynamic>;
    expect(body['subscription']['endpoint'], 'https://web.push.apple.com/abc');
    expect(body['lang'], 'en');
    expect((body['matches'] as List).single['id'], '701');
    expect(p.active, isTrue);

    await p.sync(store);
    expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
    await store.saveBet(bet(id: '702'));
    await p.sync(store);
    expect(requests.where((r) => r.method == 'PUT'), hasLength(2));

    await p.disable(store);
    expect(requests.last.method, 'DELETE');
    expect(jsonDecode(requests.last.body), {'endpoint': 'https://web.push.apple.com/abc'});
    expect(p.active, isFalse);
  });

  test('refused notifications: nothing is sent', () async {
    channel.allowed = false;
    final p = push();
    expect(await p.enable(store), isFalse);
    await p.sync(store);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  test('while the server sends the alerts the app does not show its own', () async {
    final sink = ListSink();
    now = kickoff.subtract(const Duration(minutes: 5));
    var feed = match(MatchState.scheduled);
    final service = LiveAlertService(
      store: store,
      api: FixturesApi(),
      sink: sink,
      push: push(),
      clock: () => now,
      read: (ms) async => {for (final m in ms) m.id: feed},
    );
    await service.poll();
    feed = match(MatchState.live, h: '0', a: '0');
    now = now.add(const Duration(minutes: 6));
    expect([for (final a in await service.poll()) a.title], ['Kick-off: Arsenal vs Chelsea']);
    expect(sink.shown, isEmpty);
    expect(requests.where((r) => r.method == 'PUT'), isNotEmpty);
  });
}
