import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../logic/live_alerts.dart';
import 'fixtures.dart';
import 'store.dart';

/// Preference keys. Alerts are on unless the user turns them off.
const alertsEnabledPref = 'alerts.enabled';
const _seenPref = 'alerts.seen';
const _askedPref = 'alerts.asked';

/// Where alerts go: Android notifications in the app, a list in tests.
abstract class AlertSink {
  /// Asks to show notifications (Android 13+). Returns whether allowed.
  Future<bool> requestPermission();
  Future<void> show(LiveAlert alert);
}

/// Polls the live feed for the matches behind open bets once a minute while
/// the app runs (open or in the background until Android stops it) and
/// raises a notification on kick-off, each score change and full time. Each
/// match has one notification that updates as the game goes on.
class LiveAlertService {
  LiveAlertService({
    required this.store,
    required FixturesApi api,
    required this.sink,
    this.every = const Duration(minutes: 1),
    Future<Map<String, Match>> Function(List<Match>)? read,
    DateTime Function()? clock,
  })  : _read = read ?? ((ms) => api.refreshMatches(ms, refresh: true)),
        _clock = clock ?? DateTime.now;

  final BankStore store;
  final AlertSink sink;
  final Duration every;
  final Future<Map<String, Match>> Function(List<Match>) _read;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => poll());
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One round: reads the watched matches and shows what changed. Returns
  /// the alerts it showed.
  Future<List<LiveAlert>> poll() async {
    if (_busy) return const [];
    _busy = true;
    try {
      return await _poll();
    } catch (e) {
      debugPrint('Live alerts: $e');
      return const [];
    } finally {
      _busy = false;
    }
  }

  Future<List<LiveAlert>> _poll() async {
    if (await store.pref(alertsEnabledPref) == '0') return const [];
    final now = _clock().toUtc();
    final seen = MatchSnapshot.decodeAll(await store.pref(_seenPref));
    final watched = watchedMatches(store.bets, store.parlays, now, seen: seen);
    if (watched.isEmpty) return const [];
    // Asks for notification access once, the first time there is a match to
    // follow, not at install.
    if (await store.pref(_askedPref) == null) {
      await store.setPref(_askedPref, '1');
      await sink.requestPermission();
    }
    final current = await _read([for (final w in watched) w.match]);
    final out = <LiveAlert>[];
    for (final w in watched) {
      final m = current[w.match.id];
      if (m == null) continue;
      final alert = alertFor(w, seen[m.id], m);
      seen[m.id] = MatchSnapshot.of(m);
      if (alert == null) continue;
      out.add(alert);
      await sink.show(alert);
    }
    await store.setPref(_seenPref, MatchSnapshot.encodeAll(seen, now));
    return out;
  }
}

/// Android notifications through flutter_local_notifications.
class NotificationSink implements AlertSink {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static const _channel = AndroidNotificationDetails(
    'live_bets',
    'Live bet alerts',
    channelDescription: 'Kick-off, goals and full time for matches in your open bets',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.event,
  );

  Future<bool> _init() => _ready ??= () async {
        try {
          return await _plugin.initialize(
                settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
              ) ??
              false;
        } catch (e) {
          debugPrint('Notifications unavailable: $e');
          return false;
        }
      }();

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show(LiveAlert alert) async {
    if (!await _init()) return;
    await _plugin.show(
      id: alert.matchId.hashCode & 0x7fffffff,
      title: alert.title,
      body: alert.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.channelId,
          _channel.channelName,
          channelDescription: _channel.channelDescription,
          importance: _channel.importance,
          priority: _channel.priority,
          category: _channel.category,
          styleInformation: BigTextStyleInformation(alert.body),
        ),
      ),
    );
  }
}
