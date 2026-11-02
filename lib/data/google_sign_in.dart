import 'google_sign_in_stub.dart' if (dart.library.js_interop) 'google_sign_in_web.dart' as impl;

/// What the Google window gave back: the Firebase user and its tokens, or
/// an error code (Firebase's, such as auth/popup-closed-by-user).
class GoogleResult {
  const GoogleResult({this.uid, this.email, this.idToken, this.refreshToken, this.error});
  final String? uid, email, idToken, refreshToken, error;
}

/// Google sign-in through Firebase's popup, in the browser only. The phone
/// apps sign in with email until they get Google's own SDK.
abstract class GoogleSignIn {
  factory GoogleSignIn() = impl.PlatformGoogleSignIn;

  bool get supported;

  /// Gets the Google window ready (downloads what it needs) so a tap opens
  /// it at once. Call it when the sign-in page shows.
  void prepare({required String apiKey, required String project});

  /// Opens the Google window. Call it straight from a tap: browsers only
  /// allow a popup from one.
  Future<GoogleResult> signIn({required String apiKey, required String project});
}
