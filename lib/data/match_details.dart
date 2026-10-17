import 'dart:convert';

import 'fixtures.dart';

/// Everything ESPN's match summary feed (`.../summary?event=<id>`) knows about
/// one match: odds from each bookmaker, news, team form, line-ups, key events,
/// stats, head-to-head and the league table. Every section may be empty;
/// smaller leagues and future matches carry less.
class MatchDetails {
  const MatchDetails({
    this.odds = const [],
    this.news = const [],
    this.home = const TeamInfo(),
    this.away = const TeamInfo(),
    this.events = const [],
    this.stats = const [],
    this.statsAreSeason = false,
    this.h2hSummary = '',
    this.h2h = const [],
    this.table = const [],
    this.tableTitle = '',
    this.state = MatchState.other,
    this.clock = '',
    this.homeScore,
    this.awayScore,
  });

  final List<MatchOdds> odds;
  final List<NewsItem> news;
  final TeamInfo home;
  final TeamInfo away;
  final List<KeyEvent> events;

  /// (label, home, away) rows. Before kick-off ESPN sends season totals.
  final List<(String, String, String)> stats;
  final bool statsAreSeason;
  final String h2hSummary;
  final List<PastGame> h2h;
  final List<TableRow> table;
  final String tableTitle;

  /// Where the match is now, from the feed's header: state, clock ("67'",
  /// "FT") and the score once it has started.
  final MatchState state;
  final String clock;
  final int? homeScore, awayScore;
}

class NewsItem {
  const NewsItem({required this.headline, this.description = '', this.published, this.image, this.url});
  final String headline;
  final String description;
  final DateTime? published;
  final String? image;
  final String? url;
}

class TeamInfo {
  const TeamInfo({
    this.id = '',
    this.name = '',
    this.logo,
    this.record = '',
    this.points = '',
    this.form = '',
    this.lastGames = const [],
    this.leaders = const [],
    this.formation,
    this.starters = const [],
    this.subs = const [],
  });
  final String id;
  final String name;
  final String? logo;

  /// League record as W-D-L, e.g. "6-2-4".
  final String record;
  final String points;

  /// Recent results, newest first, e.g. "WDLWW".
  final String form;
  final List<PastGame> lastGames;

  /// (category, player, value), e.g. ('Goals', 'Thierno Barry', '3').
  final List<(String, String, String)> leaders;
  final String? formation;
  final List<Player> starters;
  final List<Player> subs;
}

class Player {
  const Player(this.name, this.jersey, this.position, {this.subbedIn = false, this.subbedOut = false});
  final String name;
  final String jersey;
  final String position;
  final bool subbedIn;
  final bool subbedOut;
}

enum KeyEventKind { goal, yellow, red, sub, period, other }

class KeyEvent {
  const KeyEvent({required this.clock, required this.kind, required this.text, this.side});
  final String clock;
  final KeyEventKind kind;
  final String text;

  /// 'home', 'away' or null for match events (kick-off, half-time).
  final String? side;
}

/// A past match: from one team's last five or the head-to-head list.
class PastGame {
  const PastGame({
    required this.date,
    required this.home,
    required this.away,
    required this.score,
    this.result = '',
    this.competition = '',
  });
  final DateTime? date;
  final String home;
  final String away;
  final String score;

  /// 'W', 'D' or 'L' from the team's point of view (last five only).
  final String result;
  final String competition;
}

class TableRow {
  const TableRow({
    required this.rank,
    required this.team,
    required this.teamId,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalDiff,
    required this.points,
  });
  final int rank;
  final String team;
  final String teamId;
  final String played, won, drawn, lost, goalDiff, points;
}

/// Parses the summary feed. Sections that are missing or malformed come back
/// empty rather than failing the whole page.
MatchDetails parseMatchDetails(String body) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) return const MatchDetails();
  T? safe<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  final header = safe(() => (json['header']['competitions'] as List).first as Map<String, dynamic>);
  final competitors = safe(() => (header!['competitors'] as List).cast<Map<String, dynamic>>()) ?? const [];
  Map<String, dynamic>? competitor(String side) {
    for (final c in competitors) {
      if (c['homeAway'] == side) return c;
    }
    return null;
  }

  final homeId = '${competitor('home')?['team']?['id'] ?? ''}';
  String? sideOf(Object? teamId) {
    if (teamId == null) return null;
    return '$teamId' == homeId ? 'home' : 'away';
  }

  TeamInfo team(String side) {
    final c = competitor(side) ?? const {};
    final t = (c['team'] as Map?) ?? const {};
    final id = '${t['id'] ?? ''}';
    String rec(String type) {
      for (final r in (c['record'] as List? ?? const [])) {
        if (r is Map && r['type'] == type) return '${r['displayValue'] ?? r['summary'] ?? ''}';
      }
      return '';
    }

    final last = safe(() {
          for (final g in (json['lastFiveGames'] as List)) {
            if ('${g['team']?['id']}' == id) {
              return [
                for (final e in (g['events'] as List))
                  PastGame(
                    date: DateTime.tryParse('${e['gameDate']}'),
                    home: e['atVs'] == '@' ? '${e['opponent']?['displayName'] ?? ''}' : '${t['displayName'] ?? ''}',
                    away: e['atVs'] == '@' ? '${t['displayName'] ?? ''}' : '${e['opponent']?['displayName'] ?? ''}',
                    score: '${e['score'] ?? ''}',
                    result: '${e['gameResult'] ?? ''}',
                    competition: '${e['leagueAbbreviation'] ?? e['competitionName'] ?? ''}',
                  ),
              ];
            }
          }
          return <PastGame>[];
        }) ??
        const [];

    final leaders = safe(() {
          for (final l in (json['leaders'] as List)) {
            if ('${l['team']?['id']}' != id) continue;
            return [
              for (final cat in (l['leaders'] as List))
                if ((cat['leaders'] as List?)?.isNotEmpty ?? false)
                  (
                    '${cat['displayName'] ?? cat['name']}',
                    '${cat['leaders'][0]['athlete']?['displayName'] ?? ''}',
                    _leaderValue('${cat['leaders'][0]['displayValue'] ?? ''}'),
                  ),
            ];
          }
          return <(String, String, String)>[];
        }) ??
        const [];

    final roster = safe(() {
      for (final r in (json['rosters'] as List)) {
        if (r['homeAway'] == side) return r as Map<String, dynamic>;
      }
      return null;
    });
    final players = [
      for (final p in (roster?['roster'] as List? ?? const []))
        if (p is Map)
          (
            p['starter'] == true,
            Player(
              '${p['athlete']?['displayName'] ?? ''}',
              '${p['jersey'] ?? ''}',
              '${p['position']?['abbreviation'] ?? ''}',
              subbedIn: p['subbedIn'] == true,
              subbedOut: p['subbedOut'] == true,
            ),
          ),
    ];

    return TeamInfo(
      id: id,
      name: '${t['displayName'] ?? t['name'] ?? ''}',
      logo: safe<String?>(() => (t['logos'] as List).first['href'] as String?) ?? t['logo'] as String?,
      record: rec('total'),
      points: rec('points'),
      form: '${c['form'] ?? ''}',
      lastGames: last,
      leaders: leaders,
      formation: roster?['formation'] as String?,
      starters: [for (final p in players) if (p.$1) p.$2],
      subs: [for (final p in players) if (!p.$1) p.$2],
    );
  }

  final events = safe(() => [
            for (final e in (json['keyEvents'] as List))
              KeyEvent(
                clock: '${e['clock']?['displayValue'] ?? ''}',
                kind: _kind('${e['type']?['type'] ?? ''}', e['scoringPlay'] == true),
                text: '${e['text'] ?? e['shortText'] ?? e['type']?['text'] ?? ''}',
                side: sideOf(e['team']?['id']),
              ),
          ]) ??
      const <KeyEvent>[];

  final box = safe(() => (json['boxscore']['teams'] as List).cast<Map<String, dynamic>>()) ?? const [];
  Map<String, dynamic>? boxFor(String side) {
    for (final b in box) {
      if (b['homeAway'] == side) return b;
    }
    return null;
  }

  final hs = (boxFor('home')?['statistics'] as List?) ?? const [];
  final as = (boxFor('away')?['statistics'] as List?) ?? const [];
  final stats = <(String, String, String)>[
    for (final s in hs)
      if (s is Map)
        (
          '${s['label'] ?? s['displayName'] ?? s['name']}',
          _stat(s),
          _stat(as.firstWhere((a) => a is Map && a['name'] == s['name'], orElse: () => const {}) as Map),
        ),
  ];
  final seasonStats = hs.isNotEmpty && hs.every((s) => s is Map && _seasonStatNames.contains(s['name']));

  final series = safe(() => (json['seasonseries'] as List).cast<Map<String, dynamic>>()) ?? const [];
  final h2hSeries = series.where((s) => s['type'] == 'head-to-head').firstOrNull ?? series.firstOrNull;
  final h2h = safe(() => [
            for (final e in (h2hSeries!['events'] as List))
              () {
                final cs = (e['competitors'] as List).cast<Map<String, dynamic>>();
                final h = cs.firstWhere((c) => c['homeAway'] == 'home', orElse: () => cs.first);
                final a = cs.firstWhere((c) => c['homeAway'] == 'away', orElse: () => cs.last);
                return PastGame(
                  date: DateTime.tryParse('${e['date']}'),
                  home: '${h['team']?['displayName'] ?? ''}',
                  away: '${a['team']?['displayName'] ?? ''}',
                  score: '${h['score'] ?? '-'}-${a['score'] ?? '-'}',
                );
              }(),
          ]..sort((x, y) => (y.date ?? DateTime(0)).compareTo(x.date ?? DateTime(0)))) ??
      const <PastGame>[];

  final group = safe(() => (json['standings']['groups'] as List).first as Map<String, dynamic>);
  final table = safe(() => [
            for (final e in (group!['standings']['entries'] as List))
              () {
                String st(String n) {
                  for (final s in (e['stats'] as List)) {
                    if (s['name'] == n) return '${s['displayValue'] ?? s['value'] ?? ''}';
                  }
                  return '';
                }

                return TableRow(
                  rank: int.tryParse(st('rank')) ?? 0,
                  team: '${e['team'] is Map ? e['team']['displayName'] : e['team']}',
                  teamId: '${e['id'] ?? (e['team'] is Map ? e['team']['id'] : '')}',
                  played: st('gamesPlayed'),
                  won: st('wins'),
                  drawn: st('ties'),
                  lost: st('losses'),
                  goalDiff: st('pointDifferential'),
                  points: st('points'),
                );
              }(),
          ]..sort((a, b) => a.rank.compareTo(b.rank))) ??
      const <TableRow>[];

  final news = safe(() => [
            for (final a in (json['news']['articles'] as List))
              if (a is Map && a['headline'] != null)
                NewsItem(
                  headline: '${a['headline']}',
                  description: '${a['description'] ?? ''}',
                  published: DateTime.tryParse('${a['published']}'),
                  image: safe<String?>(() => (a['images'] as List).first['url'] as String?),
                  url: safe<String?>(() => a['links']['web']['href'] as String?),
                ),
          ]) ??
      const <NewsItem>[];

  final odds = parseOddsList(json['odds']);
  final pick = parseOddsList(json['pickcenter']);
  return MatchDetails(
    odds: [
      ...odds,
      for (final p in pick)
        if (!odds.any((o) => o.provider == p.provider)) p,
    ],
    news: news,
    home: team('home'),
    away: team('away'),
    events: events,
    stats: stats,
    statsAreSeason: seasonStats,
    h2hSummary: '${h2hSeries?['summary'] ?? ''}',
    h2h: h2h,
    table: table,
    tableTitle: '${group?['header'] ?? json['standings']?['header'] ?? ''}',
    state: switch (safe(() => header!['status']['type']['state'] as String?)) {
      'pre' => MatchState.scheduled,
      'in' => MatchState.live,
      'post' => MatchState.finished,
      _ => MatchState.other,
    },
    clock: safe<String?>(() => header!['status']['type']['shortDetail'] as String?) ?? '',
    homeScore: int.tryParse('${competitor('home')?['score'] ?? ''}'),
    awayScore: int.tryParse('${competitor('away')?['score'] ?? ''}'),
  );
}

const _seasonStatNames = {'goalDifference', 'totalGoals', 'goalAssists', 'goalsConceded'};

KeyEventKind _kind(String type, bool scoring) {
  if (scoring || type.startsWith('goal') || type.contains('penalty---scored') || type == 'own-goal') {
    return KeyEventKind.goal;
  }
  if (type == 'yellow-card') return KeyEventKind.yellow;
  if (type == 'red-card' || type.contains('red')) return KeyEventKind.red;
  if (type == 'substitution') return KeyEventKind.sub;
  if (const {'kickoff', 'halftime', 'start-2nd-half', 'end-regular-time', 'full-time', 'end-of-match'}.contains(type)) {
    return KeyEventKind.period;
  }
  return KeyEventKind.other;
}

/// Percent-like stats come as fractions ("0.3"); show them as 30%.
String _stat(Map s) {
  final v = '${s['displayValue'] ?? s['value'] ?? '-'}';
  final name = '${s['name'] ?? ''}';
  if (name.endsWith('Pct') && name != 'possessionPct') {
    final d = double.tryParse(v);
    if (d != null && d <= 1) return '${(d * 100).round()}%';
  }
  if (name == 'possessionPct') return '$v%';
  return v;
}

/// "Matches: 6, Goals: 3" -> "3"
String _leaderValue(String v) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*$').firstMatch(v);
  return m?.group(1) ?? v;
}
