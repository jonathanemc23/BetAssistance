// Checks the real ESPN and TheSportsDB feeds with the app's own readers.
// The unit tests use saved answers, so they can't tell when a feed changes
// its format; this file can. It runs every morning on GitHub
// (.github/workflows/feeds.yml) and opens an issue when a check fails.
//
//   flutter test test_live
//
// Each check looks back over recent days, so an off week (an international
// break, a quiet NBA night) doesn't fail it.
import 'package:bank_track/data/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

const _timeout = Timeout(Duration(minutes: 3));

final _api = FixturesApi();

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - n);
}

/// The finished matches of [country] (only [leagues] when given) on the
/// latest of the last [days] days that has any.
Future<List<Match>> _recentFinished(String country, {Sport? sport, Set<String>? leagues, int days = 14}) async {
  final c = countryByCode(country)!;
  for (var i = 1; i <= days; i++) {
    final list = await _api.matches(c, _daysAgo(i), sport: sport, urgent: true);
    final done = list
        .where((m) => m.state == MatchState.finished && (leagues == null || leagues.contains(m.league.slug)))
        .toList();
    if (done.isNotEmpty) return done;
  }
  return const [];
}

void main() {
  group('ESPN football', () {
    late List<Match> finished;

    // The top two divisions: cup and women's matches often come without stats.
    setUpAll(() async => finished = await _recentFinished('eng', leagues: {'eng.1', 'eng.2'}, days: 21));

    test('the match list reads teams, kick-off and final scores', () {
      expect(finished, isNotEmpty, reason: 'no finished Premier League or Championship match in 21 days: the scoreboard format may have changed');
      for (final m in finished) {
        expect(m.home.name, isNotEmpty);
        expect(m.away.name, isNotEmpty);
        expect(m.kickoff.year, greaterThan(2000));
        expect(m.home.score, isNotNull, reason: '${m.home.name} vs ${m.away.name} has no score');
        expect(m.away.score, isNotNull);
      }
    }, timeout: _timeout);

    test('a finished match page has its score and stats', () async {
      final m = finished.first;
      final d = await _api.details(m);
      expect(d.state, MatchState.finished);
      expect(d.homeScore, int.tryParse(m.home.score ?? ''));
      expect(d.awayScore, int.tryParse(m.away.score ?? ''));
      expect(d.stats, isNotEmpty, reason: 'the match summary has no team stats: its format may have changed');
    }, timeout: _timeout);

    test('the stake builder reads each team\'s last games', () async {
      final m = finished.first;
      final s = await _api.stakeStats(m);
      expect(s.home.games, isNotEmpty, reason: '${m.home.name} has no past games: the schedule or box score format may have changed');
      expect(s.away.games, isNotEmpty);
    }, timeout: _timeout);

    test('the live board of all leagues answers', () async {
      // Often empty in the morning; it only has to be readable.
      await _api.liveMatches();
    }, timeout: _timeout);
  });

  group('ESPN NBA', () {
    test('the scoreboard reads games with team leaders, and a box score its players', () async {
      List<dynamic> games = const [];
      for (var i = 1; i <= 7 && games.isEmpty; i++) {
        games = await _api.nbaGames(_daysAgo(i));
      }
      expect(games, isNotEmpty, reason: 'no NBA game in 7 days: the scoreboard format may have changed');
      final g = games.first;
      expect(g.home, isNotEmpty);
      expect(g.away, isNotEmpty);

      final box = await _api.nbaBoxScore(g.id);
      expect(box, isNotNull, reason: 'the summary of game ${g.id} could not be read');
      expect(box!.finished, isTrue);
      expect(box.players.length, greaterThan(10), reason: 'too few players in the box score of game ${g.id}');
    }, timeout: _timeout);
  });

  group('TheSportsDB', () {
    test('a league only TheSportsDB has (Cyprus) reads its recent matches', () async {
      final finished = await _recentFinished('cyp', days: 21);
      expect(finished, isNotEmpty, reason: 'no finished Cyprus match in 21 days: the free feed may have changed');
      for (final m in finished) {
        expect(m.id, startsWith('tsdb:'));
        expect(m.home.name, isNotEmpty);
        expect(m.home.score, isNotNull);
      }
    }, timeout: _timeout);
  });
}
