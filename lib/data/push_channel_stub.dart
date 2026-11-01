import 'push_channel.dart';

/// Phones use flutter_local_notifications instead.
class PlatformPushChannel implements PushChannel {
  @override
  bool get supported => false;
  @override
  bool get permitted => false;
  @override
  Future<void> register() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<Map<String, dynamic>?> subscribe(String serverKey) async => null;
  @override
  Future<Map<String, dynamic>?> current() async => null;
  @override
  Future<String?> unsubscribe() async => null;
}
