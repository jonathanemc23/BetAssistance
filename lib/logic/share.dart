import 'dart:convert';

import '../data/models.dart';
import 'stats.dart';

/// Share links: the bet is encoded in the link itself (no server), so anyone
/// with Bank Track can open it and get the same bet pre-filled.
///
/// Formats accepted when opening:
///   https://jonathanemc23.github.io/BetAssistance/b/#<code>  (web landing page)
///   banktrack://bet?d=<code>                                (opens the app directly)
///   <code>                                                  (pasted on its own)
class BetLink {
  static const webBase = 'https://jonathanemc23.github.io/BetAssistance/b/';
  static const scheme = 'banktrack';

  /// Compact JSON, base64url without padding. Results, ids and notes are
  /// left out: the receiver gets the bet, not the sender's outcome.
  static String encode(Bet b) {
    final m = <String, Object?>{
      'v': 1,
      't': b.type.name,
      'o': _round(b.odds),
      if (b.stake > 0) 'k': _round(b.stake),
      if (b.book.isNotEmpty) 'b': b.book,
      if (b.isParlay)
        'l': [
          for (final l in b.legs)
            {'s': l.selection, if (l.event.isNotEmpty) 'e': l.event, 'p': l.sport, 'o': _round(l.odds)},
        ]
      else ...{
        's': b.selection,
        if (b.event.isNotEmpty) 'e': b.event,
        'p': b.sport,
      },
    };
    return base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  }

  static String webLink(Bet b) => '$webBase#${encode(b)}';
  static String appLink(Bet b) => '$scheme://bet?d=${encode(b)}';

  /// Message for the share sheet: readable summary plus the link.
  static String shareText(Bet b, Settings s) {
    final odds = formatOdds(b.odds, s.oddsFormat);
    final lines = <String>[
      if (b.isParlay) ...[
        '${b.legs.length}-leg parlay @ $odds',
        for (final l in b.legs) '• ${l.selection}${l.event.isEmpty ? '' : ' (${l.event})'} @ ${formatOdds(l.odds, s.oddsFormat)}',
      ] else
        '${b.selection}${b.event.isEmpty ? '' : ' (${b.event})'} @ $odds',
      '',
      'Open it in Bank Track: ${webLink(b)}',
    ];
    return lines.join('\n');
  }

  /// Decodes any accepted format. Returns null when the text isn't a bet link.
  static Bet? decode(String input, {required String today, required String created}) {
    final code = _extractCode(input.trim());
    if (code == null) return null;
    try {
      final padded = code.padRight(code.length + (4 - code.length % 4) % 4, '=');
      final m = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
      if (m['v'] != 1) return null;
      final type = BetTypeX.parse(m['t'] as String?);
      final legs = [
        for (final l in (m['l'] as List? ?? const []).cast<Map<String, dynamic>>())
          BetLeg(
            selection: _str(l['s']),
            event: _str(l['e']),
            sport: _sport(l['p']),
            odds: (l['o'] as num).toDouble(),
          ),
      ];
      final odds = type == BetType.parlay && legs.isNotEmpty ? parlayOdds(legs) : (m['o'] as num).toDouble();
      if (odds <= 1) return null;
      return Bet(
        type: type,
        selection: type == BetType.parlay ? '${legs.length}-leg parlay' : _str(m['s']),
        event: _str(m['e']),
        sport: type == BetType.parlay && legs.isNotEmpty ? legs.first.sport : _sport(m['p']),
        date: today,
        stake: (m['k'] as num?)?.toDouble() ?? 0,
        odds: odds,
        book: _str(m['b']),
        created: created,
        legs: legs,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractCode(String s) {
    final uri = Uri.tryParse(s);
    if (uri != null && uri.scheme == scheme) return uri.queryParameters['d'];
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return uri.fragment.isNotEmpty ? uri.fragment : uri.queryParameters['d'];
    }
    // A link inside a longer message: take the part after '#'.
    final i = s.indexOf('/b/#');
    if (i >= 0) return s.substring(i + 4).split(RegExp(r'\s')).first;
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s) ? s : null;
  }

  static double _round(double v) => double.parse(v.toStringAsFixed(4));
  static String _str(Object? v) => v is String ? v : '';
  static String _sport(Object? v) => v is String && sports.contains(v) ? v : 'Other';
}
