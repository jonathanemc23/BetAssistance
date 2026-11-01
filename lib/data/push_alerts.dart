import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../logic/live_alerts.dart';
import 'push_channel.dart';
import 'store.dart';

/// The alert server (backend/, push/), set at build time with
/// `--dart-define=PUSH_SERVER=https://...`. Empty: no server, alerts come
/// only from the app while it is open.
const pushServer = String.fromEnvironment('PUSH_SERVER');

const _keyPref = 'push.key';
const _sentPref = 'push.sent';

/// Live alerts with the app closed, for the web app. The server can't see
/// the bets (they stay on the phone), so the app tells it which matches have
/// money on them, and the server follows those and sends kick-off, goals and
/// full time by Web Push. The app sends the list when it opens and whenever
/// it changes.
class PushAlerts {
  PushAlerts({this.server = pushServer, PushChannel? channel, http.Client? client, DateTime Function()? clock})
      : channel = channel ?? PushChannel(),
        _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// The one the app uses.
  static PushAlerts instance = PushAlerts();

  final String server;
  final PushChannel channel;
  final http.Client _client;
  final DateTime Function() _clock;

  /// When the server last took the list: while recent, it sends the alerts
  /// and the app doesn't show its own, so none come twice.
  DateTime? _synced;

  bool get available => server.isNotEmpty && channel.supported;

  /// Whether the server is sending this phone's alerts.
  bool get active => _synced != null && _clock().difference(_synced!) < const Duration(minutes: 10);

  Uri _url(String path) => Uri.parse('${server.replaceAll(RegExp(r'/+$'), '')}$path');

  /// At start: registers the service worker and keeps the server's key at
  /// hand, so a tap on the alerts switch can subscribe straight away.
  Future<void> prepare(BankStore store) async {
    if (!available) return;
    await channel.register();
    try {
      final res = await _client.get(_url('/push/key')).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final key = (jsonDecode(res.body) as Map<String, dynamic>)['key'] as String?;
        if (key != null && key.isNotEmpty) await store.setPref(_keyPref, key);
      }
    } catch (e) {
      debugPrint('Push key: $e');
    }
  }

  /// Switching alerts on, from a tap. Asks first, before anything else, as
  /// Safari only shows the prompt for a tap. Returns whether allowed.
  Future<bool> enable(BankStore store) async {
    final allowed = await channel.requestPermission();
    if (!allowed) return false;
    await store.setPref(_sentPref, '');
    await sync(store);
    return true;
  }

  /// Switching alerts off: the server forgets this phone.
  Future<void> disable(BankStore store) async {
    _synced = null;
    try {
      final endpoint = await channel.unsubscribe();
      await store.setPref(_sentPref, '');
      if (endpoint != null) {
        await _client.delete(_url('/push/devices'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'endpoint': endpoint}));
      }
    } catch (e) {
      debugPrint('Push off: $e');
    }
  }

  /// Sends the matches with open bets when they changed, or every few hours
  /// so the server knows the phone is still there.
  Future<void> sync(BankStore store) async {
    if (!available || !channel.permitted) return;
    try {
      var key = await store.pref(_keyPref);
      if (key == null || key.isEmpty) {
        await prepare(store);
        key = await store.pref(_keyPref);
      }
      if (key == null || key.isEmpty) return;
      final sub = await channel.subscribe(key);
      if (sub == null) return;
      final now = _clock();
      final body = jsonEncode({
        'subscription': sub,
        'lang': L10n.spanish ? 'es' : 'en',
        'matches': pushMatches(store.bets, store.parlays, now.toUtc()),
      });
      final last = (await store.pref(_sentPref))?.split('|');
      final at = last == null || last.length != 2 ? null : DateTime.tryParse(last[0]);
      if (at != null && last![1] == '${body.hashCode}' && now.difference(at) < const Duration(hours: 6)) {
        _synced = now;
        return;
      }
      final res = await _client
          .put(_url('/push/devices'), headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _synced = now;
        await store.setPref(_sentPref, '${now.toIso8601String()}|${body.hashCode}');
      } else {
        debugPrint('Push sync: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('Push sync: $e');
    }
  }
}
