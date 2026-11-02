import 'google_sign_in.dart';

class PlatformGoogleSignIn implements GoogleSignIn {
  @override
  bool get supported => false;
  @override
  void prepare({required String apiKey, required String project}) {}

  @override
  Future<GoogleResult> signIn({required String apiKey, required String project}) async =>
      const GoogleResult(error: 'unsupported');
}
