import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../logic/live_alerts.dart';
import 'bet_settler.dart';
import 'fixtures.dart';
import 'push_alerts.dart';
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
/// match has one notification that updates as the game goes on. With a
/// [settler], results go into the bets on their own: when the app starts,
/// after each full time and every [settleEvery] in between. With [push]
/// (the web app), the alert server is kept up to date with the matches and
/// sends the alerts itself, also with the app closed.
class LiveAlertService {
  LiveAlertService({
    required this.store,
    required FixturesApi api,
    required this.sink,
    this.settler,
    this.push,
    this.every = const Duration(minutes: 1),
    this.settleEvery = const Duration(minutes: 10),
    Future<Map<String, Match>> Function(List<Match>)? read,
    DateTime Function()? clock,
  })  : // A background read: what's on screen goes first.
        _read = read ?? ((ms) => api.refreshMatches(ms, refresh: true, urgent: false)),
        _clock = clock ?? DateTime.now;

  final BankStore store;
  final AlertSink sink;
  final BetSettler? settler;
  final PushAlerts? push;
  final Duration every;
  final Duration settleEvery;
  DateTime? _settled;
  final Future<Map<String, Match>> Function(List<Match>) _read;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _busy = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => poll());
    _askOnce().then((_) => push?.prepare(store)).then((_) => poll());
  }

  /// Asks for notification access once, when the app starts with alerts on,
  /// so it is allowed before the first match to follow comes up.
  Future<void> _askOnce() async {
    try {
      // Browsers only show the prompt after a tap (switching alerts on in
      // Settings) and may block a site that asks on its own.
      if (kIsWeb) return;
      if (await store.pref(alertsEnabledPref) == '0' || await store.pref(_askedPref) != null) return;
      await store.setPref(_askedPref, '1');
      await sink.requestPermission();
    } catch (e) {
      debugPrint('Live alerts: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One round: reads the watched matches and shows what changed, then
  /// puts in the results of bets whose matches are over when it's time.
  /// Returns the alerts it showed.
  Future<List<LiveAlert>> poll() async {
    if (_busy) return const [];
    _busy = true;
    final out = <LiveAlert>[];
    try {
      if (push != null && await store.pref(alertsEnabledPref) != '0') await push!.sync(store);
    } catch (e) {
      debugPrint('Push alerts: $e');
    }
    try {
      out.addAll(await _poll());
    } catch (e) {
      debugPrint('Live alerts: $e');
    }
    try {
      out.addAll(await _settle(fullTime: out.any((a) => a.kind == AlertKind.finalResult)));
    } catch (e) {
      debugPrint('Auto-settle: $e');
    }
    _busy = false;
    return out;
  }

  Future<List<LiveAlert>> _settle({required bool fullTime}) async {
    final s = settler;
    if (s == null) return const [];
    final now = _clock();
    if (!fullTime && _settled != null && now.difference(_settled!) < settleEvery) return const [];
    _settled = now;
    final done = await s.run();
    if (done.isEmpty || await store.pref(alertsEnabledPref) == '0') return const [];
    for (final a in done) {
      await sink.show(a);
    }
    return done;
  }

  Future<List<LiveAlert>> _poll() async {
    if (await store.pref(alertsEnabledPref) == '0') return const [];
    final now = _clock().toUtc();
    final seen = MatchSnapshot.decodeAll(await store.pref(_seenPref));
    final watched = watchedMatches(store.bets, store.parlays, now, seen: seen);
    if (watched.isEmpty) return const [];
    final current = await _read([for (final w in watched) w.match]);
    final out = <LiveAlert>[];
    for (final w in watched) {
      final m = current[w.match.id];
      if (m == null) continue;
      final alert = alertFor(w, seen[m.id], m);
      seen[m.id] = MatchSnapshot.of(m);
      if (alert == null) continue;
      out.add(alert);
      // The server sent this one already.
      if (push?.active != true) await sink.show(alert);
    }
    await store.setPref(_seenPref, MatchSnapshot.encodeAll(seen, now));
    return out;
  }
}

/// Android and iPhone notifications through flutter_local_notifications.
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
                settings: const InitializationSettings(
                  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
                  // Asked for in requestPermission, when alerts are switched on.
                  iOS: DarwinInitializationSettings(
                    requestAlertPermission: false,
                    requestBadgePermission: false,
                    requestSoundPermission: false,
                  ),
                  web: WebInitializationSettings(),
                ),
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
      if (android != null) return await android.requestNotificationsPermission() ?? true;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? true;
      final web = _plugin.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>();
      return await web?.requestNotificationsPermission() ?? true;
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
        iOS: const DarwinNotificationDetails(threadIdentifier: 'live_bets'),
      ),
    );
  }
}
