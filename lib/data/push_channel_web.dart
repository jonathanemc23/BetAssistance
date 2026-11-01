import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'push_channel.dart';

/// Web Push through web/push_sw.js.
class PlatformPushChannel implements PushChannel {
  Future<web.ServiceWorkerRegistration>? _reg;

  @override
  bool get supported =>
      globalContext.has('PushManager') &&
      globalContext.has('Notification') &&
      (web.window.navigator as JSObject).has('serviceWorker');

  @override
  bool get permitted => supported && web.Notification.permission == 'granted';

  Future<web.ServiceWorkerRegistration> _ready() => _reg ??= () async {
        final sw = web.window.navigator.serviceWorker;
        // Relative to the page's base (/BetAssistance/ on GitHub Pages).
        await sw.register('push_sw.js'.toJS, web.RegistrationOptions(scope: './')).toDart;
        return sw.ready.toDart;
      }();

  @override
  Future<void> register() async {
    if (!supported) return;
    try {
      await _ready();
    } catch (_) {
      _reg = null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!supported) return false;
    if (permitted) return true;
    final answer = await web.Notification.requestPermission().toDart;
    return answer.toDart == 'granted';
  }

  @override
  Future<Map<String, dynamic>?> subscribe(String serverKey) async {
    if (!permitted) return null;
    final reg = await _ready();
    final had = await reg.pushManager.getSubscription().toDart;
    if (had != null) return _json(had);
    final sub = await reg.pushManager
        .subscribe(web.PushSubscriptionOptionsInit(userVisibleOnly: true, applicationServerKey: _bytes(serverKey).toJS))
        .toDart;
    return _json(sub);
  }

  @override
  Future<Map<String, dynamic>?> current() async {
    if (!supported) return null;
    final sub = await (await _ready()).pushManager.getSubscription().toDart;
    return sub == null ? null : _json(sub);
  }

  @override
  Future<String?> unsubscribe() async {
    if (!supported) return null;
    final sub = await (await _ready()).pushManager.getSubscription().toDart;
    if (sub == null) return null;
    final endpoint = sub.endpoint;
    await sub.unsubscribe().toDart;
    return endpoint;
  }

  static Map<String, dynamic> _json(web.PushSubscription sub) {
    final json = globalContext['JSON'] as JSObject;
    final text = json.callMethod<JSString>('stringify'.toJS, sub);
    return jsonDecode(text.toDart) as Map<String, dynamic>;
  }

  static Uint8List _bytes(String b64url) => base64Url.decode(base64Url.normalize(b64url));
}
