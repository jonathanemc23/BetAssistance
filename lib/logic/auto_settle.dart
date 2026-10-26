import '../data/fixtures.dart';
import '../data/models.dart';
import 'bet_review.dart';

/// When a bet's result is looked for: from shortly after kick-off, when a
/// match can be over, until ten days on, when the feeds have long had it.
const resultAfter = Duration(minutes: 100);
const resultWithin = Duration(days: 10);

bool dueForResult(DateTime kickoff, DateTime now) =>
    now.isAfter(kickoff.add(resultAfter)) && now.isBefore(kickoff.add(resultWithin));

/// The final score of [m], or null while it isn't over.
(int, int)? finalScore(Match m) {
  if (m.state != MatchState.finished) return null;
  final h = int.tryParse(m.home.score ?? ''), a = int.tryParse(m.away.score ?? '');
  return h == null || a == null ? null : (h, a);
}

/// Grades a pick on a finished match from its final score: won, lost or
/// push. Null when the match isn't over or the market needs more than the
/// score (corners, cards, scorers...), so the bet stays for the user.
BetStatus? gradeOnScore(String market, String selection, Match m) {
  final s = finalScore(m);
  if (s == null) return null;
  return gradePick(market, selection, m.home.name, m.away.name, s.$1, s.$2);
}

/// [m] with its league as the app lists it (a saved slug carries no sport).
Match withKnownLeague(Match m) {
  final l = leagueBySlug(m.league.slug);
  return l == null
      ? m
      : Match(id: m.id, league: l, kickoff: m.kickoff, home: m.home, away: m.away, state: m.state, detail: m.detail);
}

Match _saved(String id, String slug, String leagueName, DateTime kickoff, String event) {
  final (home, away) = splitEvent(event) ?? (event, '');
  return withKnownLeague(Match(
    id: id,
    league: League(slug, leagueName),
    kickoff: kickoff,
    home: Team(home, home, null, null),
    away: Team(away, away, null, null),
    state: MatchState.scheduled,
    detail: '',
  ));
}

/// The match a single bet was picked from, or null when it wasn't.
Match? betMatch(Bet b) => b.matchId == null || b.leagueSlug == null || b.kickoff == null
    ? null
    : _saved(b.matchId!, b.leagueSlug!, b.leagueName ?? '', b.kickoff!, b.event);

/// The match of a linked parlay leg.
Match legMatch(BetLeg l) => _saved(l.matchId!, l.leagueSlug!, l.leagueName ?? '', l.kickoff!, l.event);

/// An NBA game as a [Match], for reading its status.
Match nbaMatch(String id, String home, String away, DateTime tipoff) => _saved(id, 'nba', 'NBA', tipoff, '$home vs $away');
