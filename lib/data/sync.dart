import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'account.dart';
import 'store.dart';

enum SyncState {
  /// Signed out or accounts not set up.
  off,
  syncing,

  /// The device and the account hold the same data.
  synced,

  /// Couldn't reach the server; tried again on the next change or in a few
  /// minutes.
  offline,

  /// Both the device and the account have different data and the user has
  /// to say which to keep.
  needsChoice,
  error,
}

const _uidPref = 'sync.uid';
const _versionPref = 'sync.version';
const _hashPref = 'sync.hash';

/// Keeps the device's data and the account's copy on the server the same.
///
/// The whole of the user's data travels as one snapshot (see
/// [BankStore.snapshot]). The device remembers the account version it last
/// matched and a fingerprint of its data at that point, so on each check it
/// knows which side changed:
/// - only the device: it saves on top of that version;
/// - only the account (another device saved): it takes the account's data;
/// - both, or the first sign-in on a device that already has bets: it asks
///   the user which to keep, so nothing is overwritten unnoticed.
///
/// It checks after every change (a few seconds later, so a burst of edits
/// is one save), when the app comes back to the front and every few
/// minutes.
class SyncService extends ChangeNotifier {
  SyncService({
    required this.store,
    required this.account,
    http.Client? client,
    this.debounce = const Duration(seconds: 3),
    this.every = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final BankStore store;
  final AccountService account;
  final http.Client _client;
  final DateTime Function() _clock;
  final Duration debounce;
  final Duration every;

  SyncState state = SyncState.off;
  DateTime? lastSynced;

  /// What went wrong, for [SyncState.error].
  String? message;

  bool _running = false;
  bool _again = false;
  bool _restoring = false;
  Timer? _debounceTimer;
  Timer? _timer;

  /// The account's data while the user chooses (see [SyncState.needsChoice]).
  _Remote? _pending;

  Uri get _url => Uri.parse('${account.server.replaceAll(RegExp(r'/+$'), '')}/api/sync');

  void start() {
    store.addListener(_changed);
    account.addListener(_accountChanged);
    _timer = Timer.periodic(every, (_) => sync());
    unawaited(sync());
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    account.removeListener(_accountChanged);
    _timer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (_restoring || !account.signedIn) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, sync);
  }

  void _accountChanged() {
    if (!account.signedIn) {
      _pending = null;
      _set(SyncState.off);
    } else {
      unawaited(sync());
    }
  }

  void _set(SyncState s, [String? msg]) {
    state = s;
    message = msg;
    notifyListeners();
  }

  static String _fingerprint(String data) => sha1.convert(utf8.encode(data)).toString();

  /// Checks both sides and saves or takes whichever changed. Safe to call at
  /// any time; calls made while one runs are folded into one more run.
  Future<void> sync() async {
    if (!account.signedIn) return _set(SyncState.off);
    if (state == SyncState.needsChoice) return;
    if (_running) {
      _again = true;
      return _current;
    }
    _running = true;
    final done = Completer<void>();
    _current = done.future;
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again && account.signedIn && state != SyncState.needsChoice);
    } finally {
      _running = false;
      done.complete();
    }
  }

  Future<void>? _current;

  /// One last save before signing out. True when everything on this device
  /// is on the account, so clearing the device loses nothing.
  Future<bool> saveBeforeSignOut() async {
    _debounceTimer?.cancel();
    await sync();
    return state == SyncState.synced;
  }

  /// Signs out and clears the user's data from this device, so the next
  /// person to open the app sees nothing of it. What this device knew about
  /// the account is forgotten too, so signing in again downloads the
  /// account's data instead of saving the empty device over it.
  Future<void> signOutAndClear() async {
    _debounceTimer?.cancel();
    if (_running) await _current;
    await account.signOut();
    for (final k in [_uidPref, _versionPref, _hashPref]) {
      await store.setPref(k, '');
    }
    lastSynced = null;
    await store.clearUserData();
  }

  Future<void> _syncOnce({bool retried = false}) async {
    final uid = account.account!.uid;
    if (state != SyncState.synced) _set(SyncState.syncing);
    final token = await account.idToken();
    if (token == null) return _set(account.signedIn ? SyncState.offline : SyncState.off);

    final local = jsonEncode(await store.snapshot());
    final hash = _fingerprint(local);
    final remote = await _fetch(token);
    if (remote == null) return;

    final known = await store.pref(_uidPref) == uid;
    final base = known ? int.tryParse(await store.pref(_versionPref) ?? '') : null;
    final syncedHash = known ? await store.pref(_hashPref) : null;

    if (remote.data != null && _fingerprint(remote.data!) == hash) {
      return _matched(uid, remote.version, hash);
    }
    if (base == null) {
      // The first time this device meets this account.
      if (remote.version == 0) return _save(token, uid, local, hash, 0, retried);
      if (store.isEmpty) return _take(uid, remote);
      _pending = remote;
      return _set(SyncState.needsChoice);
    }
    final deviceChanged = hash != syncedHash;
    final accountChanged = remote.version != base;
    if (!deviceChanged && !accountChanged) return _matched(uid, base, hash);
    if (deviceChanged && !accountChanged) return _save(token, uid, local, hash, base, retried);
    if (!deviceChanged && accountChanged) return _take(uid, remote);
    _pending = remote;
    _set(SyncState.needsChoice);
  }

  Future<_Remote?> _fetch(String token) async {
    try {
      final res = await _client.get(_url, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        _set(SyncState.offline);
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _Remote((body['version'] as num?)?.toInt() ?? 0, body['data'] as String?);
    } catch (e) {
      debugPrint('Sync fetch failed: $e');
      _set(SyncState.offline);
      return null;
    }
  }

  Future<void> _save(String token, String uid, String data, String hash, int base, bool retried) async {
    try {
      final res = await _client
          .put(_url,
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: jsonEncode({'baseVersion': base, 'data': data}))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 200) {
        final version = ((jsonDecode(res.body) as Map)['version'] as num).toInt();
        return await _matched(uid, version, hash);
      }
      // Another device saved in between: look again, which asks the user
      // if both sides changed.
      if (res.statusCode == 409 && !retried) return await _syncOnce(retried: true);
      if (res.statusCode == 413) {
        return _set(SyncState.error, tr('Too much data to save on the account.'));
      }
      _set(SyncState.offline);
    } catch (e) {
      debugPrint('Sync save failed: $e');
      _set(SyncState.offline);
    }
  }

  Future<void> _take(String uid, _Remote remote) async {
    final data = remote.data;
    if (data == null) return;
    _restoring = true;
    try {
      await store.restoreSnapshot(jsonDecode(data) as Map<String, dynamic>);
    } on StateError {
      return _set(SyncState.error, tr('Your account has data from a newer version of BetPilot. Update the app to load it.'));
    } finally {
      _restoring = false;
    }
    // Loading may fill in defaults; fingerprint what the device now holds.
    final hash = _fingerprint(jsonEncode(await store.snapshot()));
    await _matched(uid, remote.version, hash);
  }

  Future<void> _matched(String uid, int version, String hash) async {
    await store.setPref(_uidPref, uid);
    await store.setPref(_versionPref, '$version');
    await store.setPref(_hashPref, hash);
    _pending = null;
    lastSynced = _clock();
    _set(SyncState.synced);
  }

  /// The user's answer for [SyncState.needsChoice]: keep the account's data
  /// (this device's is replaced) or this device's (the account's is).
  Future<void> choose({required bool keepAccount}) async {
    final remote = _pending;
    if (remote == null || !account.signedIn) return;
    final uid = account.account!.uid;
    _set(SyncState.syncing);
    if (keepAccount) {
      await _take(uid, remote);
    } else {
      final token = await account.idToken();
      if (token == null) return _set(SyncState.needsChoice);
      final local = jsonEncode(await store.snapshot());
      await _save(token, uid, local, _fingerprint(local), remote.version, false);
    }
    if (state == SyncState.needsChoice || state == SyncState.synced) return;
    _set(SyncState.needsChoice);
  }
}

class _Remote {
  const _Remote(this.version, this.data);
  final int version;
  final String? data;
}
