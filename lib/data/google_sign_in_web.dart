import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'google_sign_in.dart';

@JS('bankTrackGooglePrepare')
external void _prepare(JSString apiKey, JSString project);

@JS('bankTrackGoogleSignIn')
external JSPromise<JSString> _signIn(JSString apiKey, JSString project);

/// Calls web/google_sign_in.js, which loads Firebase's sign-in script on
/// first use and opens the Google popup.
class PlatformGoogleSignIn implements GoogleSignIn {
  @override
  bool get supported => globalContext.has('bankTrackGoogleSignIn');

  @override
  void prepare({required String apiKey, required String project}) {
    if (globalContext.has('bankTrackGooglePrepare')) _prepare(apiKey.toJS, project.toJS);
  }

  @override
  Future<GoogleResult> signIn({required String apiKey, required String project}) async {
    try {
      final json = jsonDecode((await _signIn(apiKey.toJS, project.toJS).toDart).toDart) as Map<String, dynamic>;
      return GoogleResult(
        uid: json['uid'] as String?,
        email: json['email'] as String?,
        idToken: json['idToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        error: json['error'] as String?,
      );
    } catch (e) {
      return GoogleResult(error: '$e');
    }
  }
}
