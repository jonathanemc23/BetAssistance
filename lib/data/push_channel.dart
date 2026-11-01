import 'push_channel_stub.dart' if (dart.library.js_interop) 'push_channel_web.dart' as impl;

/// The browser's Web Push: a service worker that shows what the server
/// pushes, even with the app closed (on iPhone, a home-screen web app on
/// iOS 16.4 or later). Unsupported outside the browser.
abstract class PushChannel {
  factory PushChannel() = impl.PlatformPushChannel;

  bool get supported;

  /// Registers the service worker. Safe to call more than once.
  Future<void> register();

  /// Asks to show notifications. Call it first thing in a tap handler:
  /// Safari only shows the prompt for a tap.
  Future<bool> requestPermission();

  /// Whether notifications are already allowed.
  bool get permitted;

  /// The subscription for [serverKey] (base64url), made if there is none.
  /// As JSON: {endpoint, keys: {p256dh, auth}}. Null when refused.
  Future<Map<String, dynamic>?> subscribe(String serverKey);

  /// The current subscription, without asking for anything.
  Future<Map<String, dynamic>?> current();

  /// Drops the subscription. Returns its endpoint, null when there was none.
  Future<String?> unsubscribe();
}
