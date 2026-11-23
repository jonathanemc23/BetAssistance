import 'dart:math' as math;

import '../data/fixtures.dart';
import '../data/parlay.dart';

/// A real match that may be the one behind a pick, and how alike they are
/// (0 to 1).
class MatchCandidate {
  const MatchCandidate(this.match, this.score);
  final Match match;
  final double score;
}

/// What was found for one pick: the pick itself, tied to its match when
/// only one fits well, and otherwise the matches it could be, best first.
class LegLink {
  const LegLink(this.leg, [this.candidates = const []]);
  final ParlayLeg leg;
  final List<MatchCandidate> candidates;

  /// Several matches (or one weak one) fit: the user picks.
  bool get needsPick => !leg.isLinked && candidates.isNotEmpty;
}

/// A candidate this alike, and clearly ahead of the next, is linked
/// without asking.
const _sure = 0.8, _ahead = 0.12;

/// Each team at least this alike for a match to be offered at all.
const _fits = 0.55;

/// At most this many matches are offered for one pick.
const _offered = 5;

/// Finds the real match behind picks that came from a screenshot or were
/// typed in, so they are checked like picks chosen from the Matches list.
/// Only sure matches are linked; picks already linked, or whose match isn't
/// sure, are left as they are. [dates] are the kick-offs the slip shows,
/// one per pick (null when it shows none).
Future<List<ParlayLeg>> linkLegs(FixturesApi api, List<ParlayLeg> legs, {List<DateTime?> dates = const []}) async {
  if (legs.every((l) => l.isLinked || l.sport != 'Soccer')) return legs;
  return [for (final l in await findLinks(api, legs, dates: dates)) l.leg];
}

/// Like [linkLegs], but also gives the matches a pick could be when no one
/// is sure, so the user can choose.
Future<List<LegLink>> findLinks(
  FixturesApi api,
  List<ParlayLeg> legs, {
  List<DateTime?> dates = const [],
  DateTime? now,
}) async {
  final out = <LegLink>[];
  for (final (i, l) in legs.indexed) {
    if (l.isLinked || l.sport != 'Soccer') {
      out.add(LegLink(l));
      continue;
    }
    final found = await _candidates(api, l, i < dates.length ? dates[i] : null, now ?? DateTime.now());
    final best = found.firstOrNull;
    final sure = best != null &&
        best.score >= _sure &&
        (found.length == 1 || best.score - found[1].score >= _ahead);
    out.add(sure
        ? LegLink(l.linkedTo(best.match, selection: resultPick(l.selection, best.match)))
        : LegLink(l, found));
  }
  return out;
}

/// The days searched when the slip shows no date, nearest first: picks are
/// mostly for today and the next few days. TheSportsDB is only read for the
/// first two.
const _searchDays = [0, 1, -1, 2, 3, 4];

Future<List<MatchCandidate>> _candidates(FixturesApi api, ParlayLeg leg, DateTime? hint, DateTime now) async {
  final teams = splitEvent(leg.event);
  final single = teams == null ? _teamOf(leg) : null;
  if (teams == null && single == null) return const [];

  double? scoreOf(Match m) {
    final double s;
    if (teams != null) {
      final h = teamScore(teams.$1, m.home.name), a = teamScore(teams.$2, m.away.name);
      final sh = teamScore(teams.$1, m.away.name), sa = teamScore(teams.$2, m.home.name);
      final straight = math.min(h, a) >= _fits ? (h + a) / 2 : 0.0;
      final swapped = math.min(sh, sa) >= _fits ? (sh + sa) / 2 * 0.97 : 0.0;
      // One team read well and the other not at all (a misread name): only
      // worth offering when the slip's date says it's that day's match.
      final oneSide = hint != null && math.max(math.max(h, a), math.max(sh, sa)) >= 0.9 ? 0.6 : 0.0;
      s = [straight, swapped, oneSide].reduce(math.max);
    } else {
      // Only one team known ("Chelsea to win" with no match): never sure.
      s = math.max(teamScore(single!, m.home.name), teamScore(single, m.away.name)) >= 0.85 ? 0.6 : 0.0;
    }
    if (s <= 0) return null;
    if (hint == null) return s;
    final off = m.kickoff.toLocal().difference(hint).abs();
    if (off > const Duration(hours: 36)) return null;
    // The slip's own kick-off time agrees: that's the one.
    final hasTime = hint.hour != 0 || hint.minute != 0;
    return hasTime && off <= const Duration(hours: 3) ? math.min(1.0, s + 0.1) : s;
  }

  Future<List<MatchCandidate>> search(List<DateTime> days, {required bool stopWhenSure}) async {
    final byId = <String, MatchCandidate>{};
    var reached = false;
    for (final (n, day) in days.indexed) {
      final List<Match> list;
      try {
        list = await api.allMatchesOn(day, withTsdb: n < 2);
        reached = true;
      } on FixturesException {
        continue;
      }
      for (final m in list) {
        final s = scoreOf(m);
        if (s != null && (byId[m.id]?.score ?? 0) < s) byId[m.id] = MatchCandidate(m, s);
      }
      if (stopWhenSure && byId.values.any((c) => c.score >= _sure)) break;
    }
    if (!reached) return const [];
    final anchor = hint ?? now;
    return byId.values.toList()
      ..sort((a, b) {
        final c = b.score.compareTo(a.score);
        if (c != 0) return c;
        return a.match.kickoff.difference(anchor).abs().compareTo(b.match.kickoff.difference(anchor).abs());
      });
  }

  var found = const <MatchCandidate>[];
  if (hint != null) {
    final d = DateTime(hint.year, hint.month, hint.day);
    found = await search([d, DateTime(d.year, d.month, d.day - 1), DateTime(d.year, d.month, d.day + 1)], stopWhenSure: false);
  }
  if (found.isEmpty) {
    // No date on the slip, or nothing near it (a misread date).
    hint = null;
    found = await search([for (final o in _searchDays) DateTime(now.year, now.month, now.day + o)], stopWhenSure: true);
  }
  return found.take(_offered).toList();
}

/// The team a pick names when the slip gives no match: "Chelsea to win",
/// "Arsenal FC · Ganar el partido". Null for picks that name no team.
String? _teamOf(ParlayLeg leg) {
  final text = (leg.event.trim().isNotEmpty ? leg.event : leg.selection).split(' · ').first;
  final t = plainText(text)
      .replaceAll(RegExp(r'\s+(to win|gana|o empate|or draw|y ambos.*|and both.*|\(?[+-]?\d.*)$'), '')
      .trim();
  if (t.length < 3 || RegExp(r'\d').hasMatch(t)) return null;
  if (RegExp(r'^(draw|empate|x|si|no|yes|over|under|mas|menos|ambos|both)\b').hasMatch(t)) return null;
  return t;
}

/// Short forms bookmakers use for words in team names.
const _aliases = {
  'utd': 'united',
  'st': 'saint',
  'atl': 'atletico',
  'ath': 'athletic',
  'dep': 'deportivo',
  'ind': 'independiente',
  'indep': 'independiente',
  'nac': 'nacional',
  'int': 'internacional',
  'spurs': 'tottenham',
  'wolves': 'wolverhampton',
  'psg': 'paris',
  'barca': 'barcelona',
  'gladbach': 'monchengladbach',
};

/// How alike two names for a team are, from 0 to 1: 1 for the same club as
/// [sameTeam] sees it, high for short forms ("Man Utd", "Atl. Madrid") and
/// one or two misread letters ("Chelsae"), low for different clubs that
/// share a word ("Real Madrid", "Real Betis").
double teamScore(String a, String b) {
  if (sameTeam(a, b)) return 1;
  final wa = teamWords(a).toList(), wb = teamWords(b).toList();
  if (wa.isEmpty || wb.isEmpty) return 0;
  final (small, big) = wa.length <= wb.length ? (wa, wb) : (wb, wa);
  final used = <int>{};
  var sum = 0.0;
  for (final w in small) {
    var best = 0.0;
    int? at;
    for (final (i, v) in big.indexed) {
      if (used.contains(i)) continue;
      final s = _wordScore(w, v);
      if (s > best) {
        best = s;
        at = i;
      }
    }
    if (at != null) used.add(at);
    sum += best;
  }
  final covered = sum / small.length;
  final both = 2 * sum / (small.length + big.length);
  return math.max(both, covered * 0.85);
}

double _wordScore(String a, String b) {
  if (a == b) return 1;
  if ((_aliases[a] ?? a) == (_aliases[b] ?? b)) return 1;
  final (short, long) = a.length <= b.length ? (a, b) : (b, a);
  if (short.length >= 3 && long.startsWith(short)) return 0.9;
  if (short.length >= 4) {
    final d = _distance(a, b);
    if (d <= 1) return 0.85;
    if (d <= 2 && short.length >= 7) return 0.8;
  }
  return 0;
}

/// Letters to change, add or drop to turn [a] into [b].
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)].reduce(math.min);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// A plain match-result pick in the app's own words ("Como to win",
/// "Draw"), so the check can price it; any other market keeps its text.
String resultPick(String selection, Match m) {
  final parts = selection.split(' · ');
  final pick = parts.first.trim();
  final market = parts.length > 1 ? parts.sublist(1).join(' · ').toLowerCase() : '';
  final plain = market.isEmpty || RegExp(r'^(1x2|resultado( final)?|ganador( del partido)?|match result|full time result|tiempo reglamentario)$').hasMatch(market.trim());
  if (!plain) return selection;
  final p = pick.toLowerCase().replaceAll(RegExp(r'\s+(to win|gana)$'), '');
  if (const {'x', 'draw', 'empate', 'empate (x)'}.contains(p)) return 'Draw';
  final home = teamScore(p, m.home.name), away = teamScore(p, m.away.name);
  if (p == '1' || (home >= _sure && home > away)) return '${m.home.name} to win';
  if (p == '2' || (away >= _sure && away > home)) return '${m.away.name} to win';
  return selection;
}
