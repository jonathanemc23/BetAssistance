import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real ESPN responses (trimmed) saved in test/data.
String data(String name) => File('test/data/$name').readAsStringSync();

void main() {
  test('scoreboard odds in DraftKings shape give home, draw and away', () {
    final m = parseScoreboard(data('espn_scoreboard_draftkings.json'), const League('eng.1', 'Premier League')).single;
    final o = m.odds!;
    expect(o.home, closeTo(3.15, 1e-9)); // +215
    expect(o.draw, closeTo(3.7, 1e-9)); // +270
    expect(o.away, closeTo(2.2, 1e-9)); // +120
    expect(o.totalLine, 2.5);
    expect(o.over, closeTo(1 + 100 / 155, 1e-9));
    expect(o.under, closeTo(2.25, 1e-9));
  });

  test('summary before kick-off: odds from both books, news, form, table, head-to-head', () {
    final d = parseMatchDetails(data('espn_summary_pre.json'));
    expect(d.odds.map((o) => o.provider), containsAll(['DraftKings', 'Bet 365']));
    final b365 = d.odds.firstWhere((o) => o.provider == 'Bet 365');
    expect([b365.home, b365.draw, b365.away], [3.0, 3.8, 2.2]); // nested odds.value on home/away
    expect(b365.extras.map((e) => e.$1), contains('Double chance 1X'));
    expect(d.news, isNotEmpty);
    expect(d.news.first.url, startsWith('https://'));
    expect(d.home.name, 'Everton');
    expect(d.away.name, 'Chelsea');
    expect(d.home.form, 'DWWDD');
    expect(d.home.record, '2-4-0');
    expect(d.home.lastGames, hasLength(5));
    expect(d.home.leaders.first.$1, 'Goals');
    expect(d.home.leaders.first.$3, '3');
    expect(d.table.first.rank, 1);
    expect(d.table.any((r) => r.team == 'Everton'), isTrue);
    expect(d.h2h, isNotEmpty);
    expect(d.h2hSummary, contains('series'));
    expect(d.statsAreSeason, isTrue);
    expect(d.home.starters, isEmpty);
  });

  test('teams from different zones (Argentina) get both groups, home first', () {
    final d = parseMatchDetails(data('espn_summary_arg_zones.json'));
    expect(d.tableGroups, hasLength(2));
    expect(d.tableGroups[0].title, 'Group with Banfield');
    expect(d.tableGroups[1].title, 'Group with Lanús');
    expect(d.tableGroups[0].rows.any((r) => r.team == 'Banfield'), isTrue);
    expect(d.tableGroups[1].rows.any((r) => r.team == 'Lanús'), isTrue);
    expect(d.table, hasLength(30));
    expect(d.table.where((r) => r.team == 'Banfield' || r.team == 'Lanús'), hasLength(2));
  });

  test('teams in the same group keep one table', () {
    final d = parseMatchDetails(data('espn_summary_pre.json'));
    expect(d.tableGroups, isEmpty);
  });

  test('summary after full time: line-ups, key events and match stats', () {
    final d = parseMatchDetails(data('espn_summary_col.json'));
    expect(d.home.formation, '4-2-3-1');
    expect(d.home.starters, hasLength(11));
    expect(d.home.subs, isNotEmpty);
    expect(d.events.where((e) => e.kind == KeyEventKind.goal), hasLength(1));
    expect(d.events.where((e) => e.kind == KeyEventKind.yellow), isNotEmpty);
    expect(d.events.firstWhere((e) => e.kind == KeyEventKind.goal).side, 'away');
    expect(d.statsAreSeason, isFalse);
    final poss = d.stats.firstWhere((s) => s.$1 == 'Possession');
    expect(poss.$2, '59.9%');
    expect(poss.$3, '40.1%');
  });

  test('summary with commentary: every shot with where it was taken from', () {
    final d = parseMatchDetails(data('espn_summary_shots.json'));
    // Leeds 1-1 Manchester United: 12 and 13 attempts.
    expect(d.shots.where((s) => s.side == 'home'), hasLength(12));
    expect(d.shots.where((s) => s.side == 'away'), hasLength(13));
    expect(d.shots.where((s) => s.kind == ShotKind.goal), hasLength(2));
    expect(d.shots.where((s) => s.kind == ShotKind.blocked), hasLength(8));
    final goal = d.shots.firstWhere((s) => s.kind == ShotKind.goal && s.side == 'away');
    expect(goal.player, 'Bryan Mbeumo');
    expect(goal.x, greaterThan(83)); // inside the box
    expect(d.statValues['wonCorners'], ('2', '3'));
    expect(d.home.color, isNotNull);
    expect(d.home.starters.first.shortName, isNotEmpty);
    expect(d.table.first.logo, startsWith('https://'));
    expect(d.attendance, 36983);
  });

  test('basketball summary: each team\'s box score, home first, with who did not play', () {
    final d = parseMatchDetails(data('espn_nba_summary_box.json'));
    expect(d.boxScore.map((b) => b.side), ['home', 'away']);
    final bucks = d.boxScoreOf('home')!;
    expect(bucks.team, 'Milwaukee Bucks');
    expect(bucks.labels.take(3), ['MIN', 'PTS', 'FG']);
    expect(bucks.column('points'), 1);
    expect(bucks.totals[bucks.column('points')], '133');
    final giannis = bucks.players.firstWhere((p) => p.name == 'Giannis Antetokounmpo');
    expect(giannis.starter, isTrue);
    expect(giannis.played, isTrue);
    expect(giannis.at(bucks.column('points')), '26');
    expect(giannis.headshot, startsWith('https://'));
    final kings = d.boxScoreOf('away')!;
    expect(kings.players.where((p) => !p.played), hasLength(5));
    expect(kings.players.where((p) => p.starter), hasLength(5));
  });

  test('a newer live read updates the score and box score, keeping what was added later', () {
    final first = parseMatchDetails(data('espn_nba_summary_box.json'))
        .withHistory(MatchHistory(h2h: [PastGame(date: DateTime(2025), home: 'A', away: 'B', score: '1-0')]));
    const fresh = MatchDetails(state: MatchState.live, clock: 'Q4 2:10', homeScore: 120, awayScore: 118);
    final d = first.withLiveFrom(fresh);
    expect(d.state, MatchState.live);
    expect(d.clock, 'Q4 2:10');
    expect(d.homeScore, 120);
    expect(d.h2h, hasLength(1));
    // A read without a box score keeps the last one rather than blanking the tab.
    expect(d.boxScore, hasLength(2));
  });
}
