import '../data/fixtures.dart';
import '../data/parlay.dart';

/// Finds the real match behind picks that came from a screenshot or were
/// typed in, so they are checked like picks chosen from the Matches list.
/// Picks already linked, or whose match isn't found, are left as they are.
Future<List<ParlayLeg>> linkLegs(FixturesApi api, List<ParlayLeg> legs) async {
  if (legs.every((l) => l.isLinked || l.sport != 'Soccer' || splitEvent(l.event) == null)) return legs;
  final out = <ParlayLeg>[];
  for (final l in legs) {
    if (l.isLinked || l.sport != 'Soccer') {
      out.add(l);
      continue;
    }
    Match? m;
    try {
      m = await api.findMatch(l.event);
    } on FixturesException {
      m = null;
    }
    out.add(m == null ? l : l.linkedTo(m, selection: resultPick(l.selection, m)));
  }
  return out;
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
  if (p == '1' || sameTeam(p, m.home.name)) return '${m.home.name} to win';
  if (p == '2' || sameTeam(p, m.away.name)) return '${m.away.name} to win';
  return selection;
}
