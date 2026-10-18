import 'fixtures.dart';

/// A match the user starred. Keeps enough to list it and fetch it again.
class FavoriteMatch {
  const FavoriteMatch({
    required this.matchId,
    required this.leagueSlug,
    required this.leagueName,
    required this.home,
    required this.away,
    this.homeLogo,
    this.awayLogo,
    required this.kickoff,
    required this.added,
  });

  final String matchId;
  final String leagueSlug;
  final String leagueName;
  final String home;
  final String away;
  final String? homeLogo;
  final String? awayLogo;
  final DateTime kickoff; // UTC
  final String added;

  factory FavoriteMatch.fromMatch(Match m, String now) => FavoriteMatch(
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        homeLogo: m.home.logo,
        awayLogo: m.away.logo,
        kickoff: m.kickoff,
        added: now,
      );

  /// The league as the app knows it (with its TheSportsDB id), else as saved.
  League get league => leagueBySlug(leagueSlug) ?? League(leagueSlug, leagueName);

  /// The match as saved, before its current status is known.
  Match toMatch() => Match(
        id: matchId,
        league: league,
        kickoff: kickoff,
        home: Team(home, home, homeLogo, null),
        away: Team(away, away, awayLogo, null),
        state: MatchState.scheduled,
        detail: '',
      );

  Map<String, Object?> toRow() => {
        'match_id': matchId,
        'league_slug': leagueSlug,
        'league_name': leagueName,
        'home': home,
        'away': away,
        'home_logo': homeLogo,
        'away_logo': awayLogo,
        'kickoff': kickoff.toUtc().toIso8601String(),
        'added': added,
      };

  factory FavoriteMatch.fromRow(Map<String, Object?> r) => FavoriteMatch(
        matchId: r['match_id'] as String,
        leagueSlug: r['league_slug'] as String,
        leagueName: r['league_name'] as String? ?? '',
        home: r['home'] as String,
        away: r['away'] as String,
        homeLogo: r['home_logo'] as String?,
        awayLogo: r['away_logo'] as String?,
        kickoff: DateTime.parse(r['kickoff'] as String).toUtc(),
        added: r['added'] as String,
      );
}
