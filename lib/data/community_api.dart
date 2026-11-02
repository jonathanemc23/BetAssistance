import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../logic/community.dart';
import 'account.dart';

/// The community calls on the server that need the user's account: nametags
/// are checked and kept there, so no two bettors share one.
class CommunityApi {
  CommunityApi(this.account, {http.Client? client}) : _client = client ?? account.client;

  final AccountService account;
  final http.Client _client;

  Uri _url(String path, [Map<String, String>? query]) =>
      Uri.parse('${account.server.replaceAll(RegExp(r'/+$'), '')}/api$path').replace(queryParameters: query);

  Future<Map<String, String>?> _headers() async {
    final token = await account.idToken();
    return token == null ? null : {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Whether [handle] is free; null when the server can't be reached.
  Future<bool?> handleAvailable(String handle) async {
    final h = await _headers();
    if (h == null) return null;
    try {
      final res = await _client.get(_url('/profiles/available', {'handle': handle}), headers: h).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map)['available'] == true;
    } catch (_) {
      return null;
    }
  }

  /// The community profile this account made, on any device; null when it
  /// has none or the server can't be reached.
  Future<SocialProfile?> myProfile() async {
    final h = await _headers();
    if (h == null) return null;
    try {
      final res = await _client.get(_url('/me'), headers: h).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final p = (jsonDecode(res.body) as Map)['profile'] as Map;
      return SocialProfile(
        name: '${p['name'] ?? ''}',
        handle: '${p['handle']}',
        bio: '${p['bio'] ?? ''}',
        avatar: '${p['avatar'] ?? ''}',
        joined: '${p['joinedAt'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [p] as this account's profile, keeping its nametag for it alone.
  /// The error to show, or null once saved.
  Future<String?> createProfile(SocialProfile p) async {
    final h = await _headers();
    if (h == null) return tr('Sign in to join the community.');
    try {
      final res = await _client
          .post(_url('/profiles'),
              headers: h, body: jsonEncode({'handle': p.handle, 'name': p.name, 'bio': p.bio, 'avatar': p.avatar}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 201) return null;
      final error = '${(jsonDecode(res.body) as Map?)?['error'] ?? ''}';
      if (res.statusCode == 409 && error.contains('already have')) return null;
      if (res.statusCode == 409) return tr('That nametag is taken. Try another one.');
      return error.isEmpty ? tr("Couldn't save your profile. Try again.") : error;
    } catch (_) {
      return tr("Couldn't reach the community. Check your connection and try again.");
    }
  }
}
