import 'dart:convert';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/parlay.dart';
import '../l10n/l10n.dart';

/// Live alerts for matches the user has an open bet on: kick-off, every
/// score change and the final result. This file decides what to say; the
/// service in data/live_alert_service.dart polls the feed and shows it.

/// A match with money on it, and the picks riding on it.
class WatchedMatch {
  const WatchedMatch(this.match, this.sport, this.picks);

  /// The match as saved with the bet, before its current status is known.
  final Match match;
  final String sport;

  /// "Arsenal to win", "Parlay 2: Over 2.5"...
  final List<String> picks;
}

/// Matches are watched from shortly before kick-off until a few hours after,
/// or longer while the last reading still had them live.
const watchBefore = Duration(minutes: 30);
const watchAfter = Duration(hours: 4);
const watchLiveAfter = Duration(hours: 8);

/// The matches behind open bets (singles picked from the Matches list) and
/// open parlays' linked legs, that are about to start or being played at
/// [now]. [seen] is what the last poll read, by match id.
List<WatchedMatch> watchedMatches(List<Bet> bets, List<Parlay> parlays, DateTime now,
    {Map<String, MatchSnapshot> seen = const {}, Duration before = watchBefore}) {
  final byId = <String, (Match, String, List<String>)>{};
  void add(Match m, String sport, String pick) {
    final last = seen[m.id];
    if (last != null && last.state == MatchState.finished) return;
    final from = m.kickoff.subtract(before);
    final to = m.kickoff.add(last?.state == MatchState.live ? watchLiveAfter : watchAfter);
    if (now.isBefore(from) || now.isAfter(to)) return;
    final w = byId.putIfAbsent(m.id, () => (m, sport, []));
    if (pick.isNotEmpty && !w.$3.contains(pick)) w.$3.add(pick);
  }

  for (final b in bets) {
    if (b.status != BetStatus.pending || b.matchId == null || b.leagueSlug == null || b.kickoff == null) continue;
    final (home, away) = splitEvent(b.event) ?? (b.event, '');
    add(
      Match(
        id: b.matchId!,
        league: leagueBySlug(b.leagueSlug!) ?? League(b.leagueSlug!, b.leagueName ?? ''),
        kickoff: b.kickoff!,
        home: Team(home, home, null, null),
        away: Team(away, away, null, null),
        state: MatchState.scheduled,
        detail: '',
      ),
      b.sport,
      b.selection,
    );
  }
  for (final p in parlays) {
    if (!p.isOpen) continue;
    for (final l in p.legs) {
      final m = l.toMatch();
      if (m == null || l.kickoff == null || l.status != BetStatus.pending) continue;
      final league = leagueBySlug(m.league.slug);
      add(
        league == null
            ? m
            : Match(
                id: m.id, league: league, kickoff: m.kickoff, home: m.home, away: m.away, state: m.state, detail: ''),
        l.sport,
        '${p.name}: ${l.selection}',
      );
    }
  }
  return [for (final (m, sport, picks) in byId.values) WatchedMatch(m, sport, picks)];
}

/// How far ahead the alert server is told about matches with open bets.
const pushAhead = Duration(days: 7);

/// The matches the alert server follows for this phone (see
/// data/push_alerts.dart): those in open bets that start within
/// [pushAhead] or are being played, as it takes them. Only ESPN leagues:
/// the server reads ESPN's feed.
List<Map<String, Object>> pushMatches(List<Bet> bets, List<Parlay> parlays, DateTime now) => [
      for (final w in watchedMatches(bets, parlays, now, before: pushAhead))
        if (w.match.league.onEspn)
          {
            'id': w.match.id,
            'feed': '${w.match.league.knownSport.espn}/${w.match.league.slug}',
            'sport': w.sport,
            'kickoff': w.match.kickoff.toUtc().toIso8601String(),
            'home': w.match.home.name,
            'away': w.match.away.name,
            'picks': [for (final p in w.picks) trPick(p)],
          },
    ];

/// What a poll last read for a match, kept so the next poll (even after the
/// app restarts) only alerts on what changed.
class MatchSnapshot {
  const MatchSnapshot(this.state, this.home, this.away, this.kickoff);
  final MatchState state;
  final String? home, away; // scores
  final DateTime kickoff; // UTC, to drop old entries

  factory MatchSnapshot.of(Match m) => MatchSnapshot(m.state, m.home.score, m.away.score, m.kickoff);

  Map<String, Object?> toJson() =>
      {'s': state.name, 'h': home, 'a': away, 'k': kickoff.toUtc().toIso8601String()};

  factory MatchSnapshot.fromJson(Map<String, dynamic> j) => MatchSnapshot(
        MatchState.values.firstWhere((s) => s.name == j['s'], orElse: () => MatchState.other),
        j['h'] as String?,
        j['a'] as String?,
        DateTime.tryParse(j['k'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      );

  static Map<String, MatchSnapshot> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in j.entries) e.key: MatchSnapshot.fromJson(e.value as Map<String, dynamic>)};
    } catch (_) {
      return {}; // unreadable: start over
    }
  }

  /// Entries for matches that kicked off within the last two days.
  static String encodeAll(Map<String, MatchSnapshot> all, DateTime now) => jsonEncode({
        for (final e in all.entries)
          if (now.difference(e.value.kickoff) < const Duration(days: 2)) e.key: e.value.toJson(),
      });
}

enum AlertKind { kickoff, score, finalResult, settled }

class LiveAlert {
  const LiveAlert(this.kind, this.matchId, this.title, this.body);
  final AlertKind kind;
  final String matchId;
  final String title;
  final String body;

  @override
  String toString() => '$title | $body';
}

/// The alert for [now] given what the last poll read ([last], null on the
/// first reading). A first reading only records the match, so opening the
/// app halfway through a game doesn't replay it; one that is already
/// finished still reports the result.
LiveAlert? alertFor(WatchedMatch w, MatchSnapshot? last, Match now) {
  final picks = w.picks.isEmpty
      ? ''
      : trn(w.picks.length, 'Your pick: {picks}', 'Your picks: {picks}', {'picks': w.picks.map(trPick).join(', ')});
  String line(String extra) => [extra, picks].where((s) => s.isNotEmpty).join('\n');
  final score = '${now.home.name} ${now.home.score ?? 0}-${now.away.score ?? 0} ${now.away.name}';

  if (now.state == MatchState.finished) {
    if (last?.state == MatchState.finished) return null;
    return LiveAlert(AlertKind.finalResult, now.id, tr('Full time: {score}', {'score': score}), line(''));
  }
  if (now.state != MatchState.live || last == null) return null;
  if (last.state != MatchState.live) {
    final started = (now.home.score ?? '0') == '0' && (now.away.score ?? '0') == '0';
    return LiveAlert(AlertKind.kickoff, now.id, started ? tr('Kick-off: {match}', {'match': now.title}) : tr('Under way: {score}', {'score': score}),
        line(now.detail.isEmpty ? (now.league.name) : '${now.detail} · ${now.league.name}'));
  }
  if (last.home == now.home.score && last.away == now.away.score) return null;
  final before = _total(last.home, last.away), after = _total(now.home.score, now.away.score);
  final title = after < before
      ? tr('Score corrected: {score}', {'score': score})
      : w.sport == 'Soccer'
          ? tr('Goal! {score}', {'score': score})
          : tr('Score update: {score}', {'score': score});
  return LiveAlert(AlertKind.score, now.id, title, line(now.detail));
}

int _total(String? a, String? b) => (int.tryParse(a ?? '') ?? 0) + (int.tryParse(b ?? '') ?? 0);
