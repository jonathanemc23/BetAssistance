import 'dart:convert';
import 'dart:io';

import 'package:bank_track/data/account.dart';
import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/google_sign_in.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/data/sync.dart';
import 'package:bank_track/ui/account_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Firebase's sign-in API and the server's /api/sync, in memory.
class FakeCloud {
  final users = <String, ({String uid, String password})>{};
  final data = <String, ({int version, String data})>{};
  var now = DateTime.utc(2026, 11, 1, 12);
  var refreshes = 0;
  var saves = 0;

  http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);
  http.Response _error(String code) => _json({
        'error': {'message': code}
      }, 400);

  /// ID tokens are `id:<uid>`, refresh tokens `rt:<uid>`.
  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        if (path == '/v1/accounts:signUp' || path == '/v1/accounts:signInWithPassword') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          final email = b['email'] as String;
          final password = b['password'] as String;
          if (path.endsWith('signUp')) {
            if (users.containsKey(email)) return _error('EMAIL_EXISTS');
            if (password.length < 6) return _error('WEAK_PASSWORD : Password should be at least 6 characters');
            users[email] = (uid: 'uid-${users.length + 1}', password: password);
          }
          final u = users[email];
          if (u == null || u.password != password) return _error('INVALID_LOGIN_CREDENTIALS');
          return _json({
            'localId': u.uid,
            'email': email,
            'idToken': 'id:${u.uid}',
            'refreshToken': 'rt:${u.uid}',
            'expiresIn': '3600',
          });
        }
        if (path == '/v1/token') {
          refreshes++;
          final uid = req.bodyFields['refresh_token']!.substring(3);
          return _json({'id_token': 'id:$uid', 'refresh_token': 'rt:$uid', 'expires_in': '3600', 'user_id': uid});
        }
        if (path == '/api/sync') {
          final auth = req.headers['Authorization'] ?? '';
          if (!auth.startsWith('Bearer id:')) return http.Response('', 401);
          final uid = auth.substring(10);
          final current = data[uid];
          if (req.method == 'GET') {
            return _json({'version': current?.version ?? 0, 'data': current?.data});
          }
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          if ((b['baseVersion'] as int) != (current?.version ?? 0)) {
            return _json({'error': 'changed', 'version': current?.version ?? 0}, 409);
          }
          saves++;
          data[uid] = (version: (current?.version ?? 0) + 1, data: b['data'] as String);
          return _json({'version': data[uid]!.version, 'updatedAt': now.toIso8601String()});
        }
        return http.Response('not found', 404);
      });
}

class NoGoogle implements GoogleSignIn {
  @override
  bool get supported => false;
  @override
  Future<GoogleResult> signIn({required String apiKey, required String project}) async =>
      const GoogleResult(error: 'unsupported');
}

Bet bet(String selection, {double stake = 10}) =>
    Bet(selection: selection, date: '2026-10-30', stake: stake, odds: 2.0, created: '2026-10-30T10:00:00');

/// One phone: its own database, sign-in and sync.
class Device {
  Device._(this.store, this.account, this.sync);
  final BankStore store;
  final AccountService account;
  final SyncService sync;

  static Future<Device> open(String path, FakeCloud cloud) async {
    final store = BankStore(await AppDatabase.open(factory: databaseFactoryFfi, path: path));
    await store.load();
    final client = cloud.client();
    final account = AccountService(
      store: store,
      apiKey: 'test-key',
      server: 'https://server.example.com/',
      client: client,
      google: NoGoogle(),
      clock: () => cloud.now,
    );
    await account.restore();
    final sync = SyncService(store: store, account: account, client: client, clock: () => cloud.now);
    return Device._(store, account, sync);
  }

  List<String> get selections => [for (final b in store.bets) b.selection]..sort();
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late FakeCloud cloud;
  var n = 0;
  Future<Device> device() => Device.open('${dir.path}/phone${n++}.db', cloud);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_test');
    cloud = FakeCloud();
  });
  tearDown(() => dir.delete(recursive: true));

  test('sign-up and sign-in errors come back in plain words', () async {
    final a = await device();
    expect(a.account.configured, isTrue);
    expect(await a.account.signUp('laura', 'secret1'), 'Enter a valid email address.');
    expect(await a.account.signUp('laura@example.com', '123'), 'Use a password of at least 6 characters.');
    expect(await a.account.signUp('laura@example.com', 'secret1'), isNull);
    expect(a.account.account!.email, 'laura@example.com');
    await a.account.signOut();
    expect(await a.account.signUp('laura@example.com', 'secret1'),
        'There is already an account with this email. Sign in instead.');
    expect(await a.account.signIn('laura@example.com', 'wrong'), 'Wrong email or password.');
    expect(await a.account.signIn('laura@example.com', 'secret1'), isNull);
  });

  test("the account follows the user to a new phone, and each phone's changes reach the other", () async {
    final a = await device();
    await a.store.saveBet(bet('Arsenal to win'));
    await a.store.saveSettings(a.store.settings.copyWith(startBankroll: 500, currency: 'EUR'));
    await a.store.setPref('ai.key', 'sk-ant-secret');
    await a.account.signUp('laura@example.com', 'secret1');
    await a.sync.sync();
    expect(a.sync.state, SyncState.synced);
    expect(cloud.data['uid-1']!.version, 1);
    // This device's own settings stay on it.
    expect(cloud.data['uid-1']!.data, isNot(contains('sk-ant-secret')));
    expect(cloud.data['uid-1']!.data, isNot(contains('rt:uid-1')));

    // A new phone with nothing on it takes the account's data.
    final b = await device();
    await b.account.signIn('laura@example.com', 'secret1');
    await b.sync.sync();
    expect(b.sync.state, SyncState.synced);
    expect(b.selections, ['Arsenal to win']);
    expect(b.store.settings.startBankroll, 500);
    expect(b.store.settings.currency, 'EUR');
    expect(await b.store.pref('ai.key'), isNull);

    // Nothing changed: nothing is saved again.
    await b.sync.sync();
    expect(cloud.saves, 1);

    // A bet logged on the second phone shows on the first.
    await b.store.saveBet(bet('Chelsea to win'));
    await b.sync.sync();
    expect(cloud.data['uid-1']!.version, 2);
    await a.sync.sync();
    expect(a.selections, ['Arsenal to win', 'Chelsea to win']);
    expect(await a.store.pref('ai.key'), 'sk-ant-secret');
  });

  test('a phone that already has other bets asks which data to keep', () async {
    final a = await device();
    await a.store.saveBet(bet('Arsenal to win'));
    await a.account.signUp('laura@example.com', 'secret1');
    await a.sync.sync();

    final b = await device();
    await b.store.saveBet(bet('Roma to win'));
    await b.account.signIn('laura@example.com', 'secret1');
    await b.sync.sync();
    expect(b.sync.state, SyncState.needsChoice);
    expect(b.selections, ['Roma to win']);
    expect(cloud.saves, 1);

    await b.sync.choose(keepAccount: true);
    expect(b.sync.state, SyncState.synced);
    expect(b.selections, ['Arsenal to win']);

    // Both phones change before either syncs: the second to save is asked.
    await a.store.saveBet(bet('Milan to win'));
    await b.store.saveBet(bet('Inter to win'));
    await a.sync.sync();
    await b.sync.sync();
    expect(b.sync.state, SyncState.needsChoice);
    await b.sync.choose(keepAccount: false);
    expect(b.sync.state, SyncState.synced);
    await a.sync.sync();
    expect(a.selections, ['Arsenal to win', 'Inter to win']);
  });

  test('the sign-in is remembered and its token refreshed when it runs out', () async {
    final path = '${dir.path}/remember.db';
    final a = await Device.open(path, cloud);
    await a.account.signUp('laura@example.com', 'secret1');
    await a.store.saveBet(bet('Arsenal to win'));
    await a.sync.sync();
    expect(cloud.refreshes, 0);
    await a.store.saveBet(bet('Chelsea to win'));
    cloud.now = cloud.now.add(const Duration(hours: 2));
    await a.sync.sync();
    expect(cloud.refreshes, 1);
    expect(cloud.data['uid-1']!.version, 2);

    // Opened again: still signed in, then signed out on request.
    await a.store.load();
    final again = AccountService(
        store: a.store, apiKey: 'k', server: 'https://s', client: cloud.client(), google: NoGoogle());
    await again.restore();
    expect(again.account?.email, 'laura@example.com');
    await again.signOut();
    final after = AccountService(store: a.store, apiKey: 'k', server: 'https://s', client: cloud.client(), google: NoGoogle());
    await after.restore();
    expect(after.signedIn, isFalse);
  });

  test('without the Firebase key there are no accounts', () async {
    final a = await device();
    final off = AccountService(store: a.store, apiKey: '', server: 'https://s', google: NoGoogle());
    expect(off.configured, isFalse);
  });

  testWidgets('the sign-in page creates an account and shows what went wrong', (tester) async {
    // A phone screen.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final a = (await tester.runAsync(device))!;
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => LoginPage(account: a.account, atLaunch: true))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-google')), findsNothing);
    expect(find.byKey(const Key('login-not-now')), findsOneWidget);

    // The name field only shows when creating an account.
    expect(find.byKey(const Key('login-name')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('login-switch')));
    await tester.tap(find.byKey(const Key('login-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-name')), 'Laura');
    await tester.enterText(find.byKey(const Key('login-email')), 'laura@example.com');
    await tester.enterText(find.byKey(const Key('login-password')), '123');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('login-submit')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('Use a password of at least 6 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-password')), 'secret1');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('login-submit')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(a.account.account?.email, 'laura@example.com');
    expect(a.store.profileName, 'Laura');
  });
}
