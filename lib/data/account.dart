import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'google_sign_in.dart';
import 'push_alerts.dart' show pushServer;
import 'store.dart';

/// Firebase Authentication, set at build time with
/// `--dart-define=FIREBASE_API_KEY=...` (the Web API key of the Firebase
/// project). Empty: no accounts, the app works on the device only.
const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');

/// The Firebase project: the same Google Cloud project as the server.
const firebaseProject = String.fromEnvironment('FIREBASE_PROJECT', defaultValue: 'betpilot-513404');

const _uidPref = 'account.uid';
const _emailPref = 'account.email';
const _refreshPref = 'account.refresh';
const _providerPref = 'account.provider';

/// Set when the user chose "Not now" on the sign-in page at launch.
const accountSkippedPref = 'account.skipped';

/// The signed-in user.
class Account {
  const Account({required this.uid, required this.email, this.provider = 'password'});
  final String uid;
  final String email;

  /// 'password' or 'google.com'.
  final String provider;
}

/// Signs in with Firebase Authentication through its REST API, so it works
/// the same in the browser and on phones with no Firebase SDK in the app.
/// Google sign-in goes through Firebase's own popup in the browser (see
/// web/google_sign_in.js) and hands its tokens over here.
///
/// The refresh token is kept on this device only; the ID token it gives is
/// what the server checks on every call.
class AccountService extends ChangeNotifier {
  AccountService({
    required this.store,
    this.apiKey = firebaseApiKey,
    this.project = firebaseProject,
    this.server = pushServer,
    http.Client? client,
    GoogleSignIn? google,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        google = google ?? GoogleSignIn(),
        _clock = clock ?? DateTime.now;

  final BankStore store;
  final String apiKey;
  final String project;

  /// The server that keeps the account's data.
  final String server;
  final GoogleSignIn google;
  final http.Client _client;
  final DateTime Function() _clock;

  Account? account;
  String? _refreshToken;
  String? _idToken;
  DateTime? _idExpires;

  /// Accounts need the Firebase key and the server to save the data on.
  bool get configured => apiKey.isNotEmpty && server.isNotEmpty;
  bool get signedIn => account != null;
  bool get googleAvailable => google.supported;

  /// Picks up the account this device signed in with last time.
  Future<void> restore() async {
    final uid = await store.pref(_uidPref);
    final refresh = await store.pref(_refreshPref);
    if (!configured || uid == null || uid.isEmpty || refresh == null || refresh.isEmpty) return;
    account = Account(
      uid: uid,
      email: await store.pref(_emailPref) ?? '',
      provider: await store.pref(_providerPref) ?? 'password',
    );
    _refreshToken = refresh;
    notifyListeners();
  }

  /// Creates an account. Returns the error to show, or null when signed in.
  Future<String?> signUp(String email, String password) =>
      _passwordCall('accounts:signUp', email, password);

  /// Returns the error to show, or null when signed in.
  Future<String?> signIn(String email, String password) =>
      _passwordCall('accounts:signInWithPassword', email, password);

  Future<String?> _passwordCall(String method, String email, String password) async {
    email = email.trim();
    if (!email.contains('@')) return tr('Enter a valid email address.');
    if (password.isEmpty) return tr('Enter your password.');
    try {
      final res = await _client
          .post(
            Uri.https('identitytoolkit.googleapis.com', '/v1/$method', {'key': apiKey}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}),
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) return _authError(body);
      await _signedIn(
        uid: body['localId'] as String,
        email: body['email'] as String? ?? email,
        provider: 'password',
        idToken: body['idToken'] as String,
        refreshToken: body['refreshToken'] as String,
        expiresIn: int.tryParse('${body['expiresIn']}') ?? 3600,
      );
      return null;
    } catch (e) {
      debugPrint('Sign-in failed: $e');
      return tr("Couldn't reach the sign-in service. Check your connection and try again.");
    }
  }

  /// Emails a link to choose a new password. Returns the error, or null.
  Future<String?> sendPasswordReset(String email) async {
    email = email.trim();
    if (!email.contains('@')) return tr('Enter a valid email address.');
    try {
      final res = await _client
          .post(
            Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:sendOobCode', {'key': apiKey}),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'requestType': 'PASSWORD_RESET', 'email': email}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return null;
      return _authError(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e) {
      return tr("Couldn't reach the sign-in service. Check your connection and try again.");
    }
  }

  /// Google sign-in (the web app). Returns the error, or null when signed in
  /// or when the user closed the Google window.
  Future<String?> signInWithGoogle() async {
    final r = await google.signIn(apiKey: apiKey, project: project);
    if (r.error != null) {
      return switch (r.error) {
        'auth/popup-closed-by-user' || 'auth/cancelled-popup-request' || 'auth/user-cancelled' => null,
        'auth/popup-blocked' => tr('The browser blocked the Google window. Allow pop-ups for BetPilot and try again.'),
        'auth/unauthorized-domain' || 'auth/operation-not-allowed' =>
          tr('Google sign-in is not switched on for BetPilot yet. Use your email for now.'),
        'auth/network-request-failed' || 'load' =>
          tr("Couldn't reach the sign-in service. Check your connection and try again."),
        _ => tr('Google sign-in failed ({code}). Try again or use your email.', {'code': r.error}),
      };
    }
    if (r.uid == null) return null;
    await _signedIn(
      uid: r.uid!,
      email: r.email ?? '',
      provider: 'google.com',
      idToken: r.idToken!,
      refreshToken: r.refreshToken!,
      expiresIn: 3600,
    );
    return null;
  }

  Future<void> _signedIn({
    required String uid,
    required String email,
    required String provider,
    required String idToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    account = Account(uid: uid, email: email, provider: provider);
    _idToken = idToken;
    _refreshToken = refreshToken;
    _idExpires = _clock().add(Duration(seconds: expiresIn));
    await store.setPref(_uidPref, uid);
    await store.setPref(_emailPref, email);
    await store.setPref(_providerPref, provider);
    await store.setPref(_refreshPref, refreshToken);
    notifyListeners();
  }

  /// Signs out on this device. The data stays on the device and on the
  /// account.
  Future<void> signOut() async {
    account = null;
    _idToken = null;
    _refreshToken = null;
    _idExpires = null;
    for (final k in [_uidPref, _emailPref, _providerPref, _refreshPref]) {
      await store.setPref(k, '');
    }
    notifyListeners();
  }

  /// A current ID token for the server, refreshed when it is about to
  /// expire. Null when signed out or offline. An account that was deleted
  /// or disabled is signed out.
  Future<String?> idToken() async {
    if (account == null || _refreshToken == null) return null;
    final expires = _idExpires;
    if (_idToken != null && expires != null && _clock().isBefore(expires.subtract(const Duration(minutes: 5)))) {
      return _idToken;
    }
    try {
      final res = await _client.post(
        Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey}),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': _refreshToken!},
      ).timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        final code = '${(body['error'] as Map?)?['message']}';
        if (code.startsWith('TOKEN_EXPIRED') ||
            code.startsWith('USER_DISABLED') ||
            code.startsWith('USER_NOT_FOUND') ||
            code.startsWith('INVALID_REFRESH_TOKEN')) {
          await signOut();
        }
        return null;
      }
      _idToken = body['id_token'] as String;
      final refresh = body['refresh_token'] as String? ?? _refreshToken!;
      if (refresh != _refreshToken) {
        _refreshToken = refresh;
        await store.setPref(_refreshPref, refresh);
      }
      _idExpires = _clock().add(Duration(seconds: int.tryParse('${body['expires_in']}') ?? 3600));
      return _idToken;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      return null;
    }
  }

  /// Firebase's error codes, in the user's words.
  static String _authError(Map<String, dynamic> body) {
    final code = '${(body['error'] as Map?)?['message'] ?? ''}';
    if (code.startsWith('WEAK_PASSWORD')) return tr('Use a password of at least 6 characters.');
    return switch (code) {
      'EMAIL_EXISTS' => tr('There is already an account with this email. Sign in instead.'),
      'INVALID_LOGIN_CREDENTIALS' ||
      'INVALID_PASSWORD' ||
      'EMAIL_NOT_FOUND' =>
        tr('Wrong email or password.'),
      'INVALID_EMAIL' || 'MISSING_EMAIL' => tr('Enter a valid email address.'),
      'MISSING_PASSWORD' => tr('Enter your password.'),
      'USER_DISABLED' => tr('This account has been disabled.'),
      'TOO_MANY_ATTEMPTS_TRY_LATER' => tr('Too many attempts. Wait a few minutes and try again.'),
      'OPERATION_NOT_ALLOWED' => tr('Email sign-in is not switched on for BetPilot yet.'),
      _ => tr('Sign-in failed ({code}). Try again.', {'code': code}),
    };
  }
}
