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
    this.tableGroups = const [],
    this.state = MatchState.other,
    this.clock = '',
    this.homeScore,
    this.awayScore,
    this.shots = const [],
    this.statValues = const {},
    this.statNames = const [],
    this.attendance,
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

  /// The table split by group when the match's teams sit in different groups
  /// (Argentina's zones, cup groups). Empty when [table] is a single group.
  final List<TableGroup> tableGroups;

  /// Where the match is now, from the feed's header: state, clock ("67'",
  /// "FT") and the score once it has started.
  final MatchState state;
  final String clock;
  final int? homeScore, awayScore;

  /// Every attempt with where it was taken from (ESPN's commentary feed,
  /// bigger leagues only). Empty when the feed has no shot positions.
  final List<Shot> shots;

  /// The stats by ESPN's own name ("wonCorners"), as (home, away).
  final Map<String, (String, String)> statValues;

  /// ESPN's name for each row of [stats], in the same order.
  final List<String> statNames;
  final int? attendance;

  /// Only the status and score of [m], for matches no feed has details for.
  static MatchDetails statusOf(Match m) => MatchDetails(
    state: m.state,
    clock: m.detail,
    homeScore: int.tryParse(m.home.score ?? ''),
    awayScore: int.tryParse(m.away.score ?? ''),
  );

  /// These details with the status and score of [m].
  MatchDetails withStatusOf(Match m) => MatchDetails(
    odds: odds,
    news: news,
    home: home,
    away: away,
    events: events,
    stats: stats,
    statsAreSeason: statsAreSeason,
    h2hSummary: h2hSummary,
    h2h: h2h,
    table: table,
    tableTitle: tableTitle,
    tableGroups: tableGroups,
    state: m.state,
    clock: m.detail,
    homeScore: int.tryParse(m.home.score ?? ''),
    awayScore: int.tryParse(m.away.score ?? ''),
    shots: shots,
    statValues: statValues,
    statNames: statNames,
    attendance: attendance,
  );

  /// These details with the longer [history]: each team's last results and
  /// the meetings between them, when it found more than the summary has.
  MatchDetails withHistory(MatchHistory history) => MatchDetails(
    odds: odds,
    news: news,
    home: history.home.length > home.lastGames.length ? home.withLastGames(history.home.reversed.toList()) : home,
    away: history.away.length > away.lastGames.length ? away.withLastGames(history.away.reversed.toList()) : away,
    events: events,
    stats: stats,
    statsAreSeason: statsAreSeason,
    // ESPN's summary line covers this season's meetings only.
    h2hSummary: history.h2h.length > h2h.length ? '' : h2hSummary,
    h2h: history.h2h.length > h2h.length ? history.h2h : h2h,
    table: table,
    tableTitle: tableTitle,
    tableGroups: tableGroups,
    state: state,
    clock: clock,
    homeScore: homeScore,
    awayScore: awayScore,
    shots: shots,
    statValues: statValues,
    statNames: statNames,
    attendance: attendance,
  );
}

/// Each team's latest results and the latest meetings between them, newest
/// first, from the teams' schedules ([FixturesApi.history]).
class MatchHistory {
  const MatchHistory({this.home = const [], this.away = const [], this.h2h = const []});
  final List<PastGame> home;
  final List<PastGame> away;
  final List<PastGame> h2h;
}

/// One finished game from a team's schedule, with both teams' ids.
class ScheduleGame {
  const ScheduleGame({required this.id, required this.game, required this.homeId, required this.awayId});
  final String id;
  final PastGame game;
  final String homeId;
  final String awayId;
}

/// A team's finished games in one season, newest first, and that season's year.
class TeamSchedule {
  const TeamSchedule({this.season, this.games = const []});
  final int? season;
  final List<ScheduleGame> games;
}

/// Parses ESPN's team schedule feed (`.../teams/<id>/schedule`): the
/// finished games, with W, D or L from [teamId]'s side.
TeamSchedule parseSchedule(String body, String teamId) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const TeamSchedule();
  }
  if (json is! Map<String, dynamic>) return const TeamSchedule();
  final Map<String, dynamic> map = json;
  final season = _try(() => ((map['requestedSeason'] as Map?)?['year'] ?? (map['season'] as Map?)?['year']) as int?);
  final games = <ScheduleGame>[];
  for (final e in (map['events'] as List? ?? const [])) {
    try {
      final comp = (e['competitions'] as List).first as Map<String, dynamic>;
      if (comp['status']?['type']?['state'] != 'post' && e['status']?['type']?['state'] != 'post') continue;
      final cs = (comp['competitors'] as List).cast<Map<String, dynamic>>();
      final h = cs.firstWhere((c) => c['homeAway'] == 'home', orElse: () => cs.first);
      final a = cs.firstWhere((c) => c['homeAway'] == 'away', orElse: () => cs.last);
      String score(Map<String, dynamic> c) {
        final s = c['score'];
        return s is Map ? '${s['displayValue'] ?? s['value'] ?? ''}' : '${s ?? ''}';
      }

      final hs = int.tryParse(score(h)), as = int.tryParse(score(a));
      if (hs == null || as == null) continue;
      final homeId = '${h['team']?['id'] ?? h['id'] ?? ''}', awayId = '${a['team']?['id'] ?? a['id'] ?? ''}';
      final (gf, ga) = homeId == teamId ? (hs, as) : (as, hs);
      final league = e['league'];
      games.add(ScheduleGame(
        id: '${e['id'] ?? ''}',
        homeId: homeId,
        awayId: awayId,
        game: PastGame(
          date: DateTime.tryParse('${e['date']}'),
          home: '${h['team']?['displayName'] ?? ''}',
          away: '${a['team']?['displayName'] ?? ''}',
          score: '$hs-$as',
          result: gf > ga ? 'W' : gf < ga ? 'L' : 'D',
          competition: league is Map ? '${league['shortName'] ?? league['abbreviation'] ?? league['name'] ?? ''}' : '',
        ),
      ));
    } catch (_) {
      // Skip a game we can't read.
    }
  }
  games.sort((x, y) => (y.game.date ?? DateTime(0)).compareTo(x.game.date ?? DateTime(0)));
  return TeamSchedule(season: season, games: games);
}

enum ShotKind { goal, onTarget, offTarget, blocked }

/// One attempt at goal. Positions are 0-100 with the attacking team shooting
/// towards x = 100; y = 100 is the attacker's left touchline.
class Shot {
  const Shot({
    required this.side,
    required this.kind,
    required this.x,
    required this.y,
    this.goalY,
    this.endX,
    this.endY,
    this.clock = '',
    this.player = '',
    this.text = '',
  });

  /// 'home' or 'away'.
  final String side;
  final ShotKind kind;
  final double x, y;

  /// Where it crossed the goal line, across the goal (same scale as [y]).
  final double? goalY;
  final double? endX, endY;
  final String clock;
  final String player;
  final String text;
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
    this.color,
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

  /// The club colour as 0xRRGGBB, when the feed has one.
  final int? color;

  TeamInfo withLastGames(List<PastGame> games) => TeamInfo(
        id: id,
        name: name,
        logo: logo,
        record: record,
        points: points,
        form: form,
        lastGames: games,
        leaders: leaders,
        formation: formation,
        starters: starters,
        subs: subs,
        color: color,
      );
}

class Player {
  const Player(this.name, this.jersey, this.position,
      {this.subbedIn = false, this.subbedOut = false, this.shortName = ''});
  final String name;
  final String jersey;
  final String position;
  final bool subbedIn;
  final bool subbedOut;

  /// "S. Ichazo", for the line-up pitch.
  final String shortName;
}

enum KeyEventKind { goal, yellow, red, sub, period, other }

class KeyEvent {
  const KeyEvent({required this.clock, required this.kind, required this.text, this.side, this.player = '', this.playerOff = ''});
  final String clock;
  final KeyEventKind kind;
  final String text;

  /// The scorer, the booked player or the one coming on, when the feed names one.
  final String player;

  /// For a substitution, the player going off.
  final String playerOff;

  /// 'home', 'away' or null for match events (kick-off, half-time).
  final String? side;
}

/// A past match: from one team's latest results or the head-to-head list.
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

  /// 'W', 'D' or 'L' from the team's point of view (latest results only).
  final String result;
  final String competition;
}

/// One group of a league table, such as a zone, with its rows by rank.
class TableGroup {
  const TableGroup({required this.title, required this.rows});
  final String title;
  final List<TableRow> rows;
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
    this.logo,
    this.winPct = '',
    this.gamesBehind = '',
  });
  final int rank;
  final String team;
  final String teamId;
  final String played, won, drawn, lost, goalDiff, points;
  final String? logo;

  /// Leagues without draws or points (basketball, baseball) rank by these.
  final String winPct, gamesBehind;
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
              shortName: '${p['athlete']?['shortName'] ?? ''}',
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
      color: int.tryParse('${t['color'] ?? ''}', radix: 16),
    );
  }

  final events = safe(() => [
            for (final e in (json['keyEvents'] as List))
              KeyEvent(
                clock: '${e['clock']?['displayValue'] ?? ''}',
                kind: _kind('${e['type']?['type'] ?? ''}', e['scoringPlay'] == true),
                text: '${e['text'] ?? e['shortText'] ?? e['type']?['text'] ?? ''}',
                side: sideOf(e['team']?['id']),
                player: _try(() => '${(e['participants'] as List).first['athlete']['displayName']}') ?? '',
                playerOff: _try(() => '${(e['participants'] as List)[1]['athlete']['displayName']}') ?? '',
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
  final statValues = <String, (String, String)>{
    for (final s in hs)
      if (s is Map && s['name'] != null)
        '${s['name']}': (
          _stat(s),
          _stat(as.firstWhere((a) => a is Map && a['name'] == s['name'], orElse: () => const {}) as Map),
        ),
  };
  final homeName = '${competitor('home')?['team']?['displayName'] ?? ''}';
  final shots = safe(() => [
            for (final c in (json['commentary'] as List))
              if (c is Map && c['play'] is Map) ?_shot(c['play'] as Map, homeName),
          ]) ??
      const <Shot>[];
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

  // Several groups (conferences, divisions, cup groups, zones): the ones with this
  // match's teams, the home team's first. Teams from different zones get both.
  final groups = safe(() => (json['standings']['groups'] as List).cast<Map<String, dynamic>>()) ?? const [];
  final sideIds = ([...competitors]..sort((a, b) => (a['homeAway'] == 'home' ? 0 : 1).compareTo(b['homeAway'] == 'home' ? 0 : 1)))
      .map((c) => '${c['team']?['id'] ?? c['id'] ?? ''}')
      .where((id) => id.isNotEmpty)
      .toList();
  bool holds(Map<String, dynamic> g, String id) =>
      (safe(() => g['standings']['entries'] as List) ?? const []).any((e) => e is Map && '${e['id'] ?? ''}' == id);
  final picked = <Map<String, dynamic>>[];
  for (final id in sideIds) {
    final g = groups.where((g) => holds(g, id)).firstOrNull;
    if (g != null && !picked.contains(g)) picked.add(g);
  }
  if (picked.isEmpty && groups.isNotEmpty) picked.add(groups.first);
  final group = picked.firstOrNull;
  List<TableRow> rowsOf(Map<String, dynamic> g) =>
      safe(() => [
            for (final (i, e) in (g['standings']['entries'] as List).indexed)
              () {
                String st(String n) {
                  for (final s in (e['stats'] as List)) {
                    if (s['name'] == n) return '${s['displayValue'] ?? s['value'] ?? ''}';
                  }
                  return '';
                }

                return TableRow(
                  rank: int.tryParse(st('rank')) ?? i + 1,
                  team: '${e['team'] is Map ? e['team']['displayName'] : e['team']}',
                  teamId: '${e['id'] ?? (e['team'] is Map ? e['team']['id'] : '')}',
                  played: st('gamesPlayed'),
                  won: st('wins'),
                  drawn: st('ties'),
                  lost: st('losses'),
                  goalDiff: st('pointDifferential'),
                  points: st('points'),
                  logo: safe<String?>(() => (e['logo'] as List).first['href'] as String?),
                  winPct: st('winPercent'),
                  gamesBehind: st('gamesBehind'),
                );
              }(),
          ]..sort((a, b) => a.rank.compareTo(b.rank))) ??
      const <TableRow>[];
  final tableGroups = [for (final g in picked) (g, rowsOf(g))];
  final table = [for (final (_, rows) in tableGroups) ...rows];
  // Zones often share one header, so each is named after the match's team in it.
  String groupTitle(Map<String, dynamic> g, List<TableRow> rows) {
    final header = '${g['header'] ?? ''}';
    if (picked.where((o) => '${o['header'] ?? ''}' == header).length == 1 && header.isNotEmpty) return header;
    final team = rows.where((r) => sideIds.contains(r.teamId)).firstOrNull?.team;
    return team == null ? header : 'Group with $team';
  }

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
    tableGroups: tableGroups.length < 2
        ? const []
        : [for (final (g, rows) in tableGroups) TableGroup(title: groupTitle(g, rows), rows: rows)],
    state: switch (safe(() => header!['status']['type']['state'] as String?)) {
      'pre' => MatchState.scheduled,
      'in' => MatchState.live,
      'post' => MatchState.finished,
      _ => MatchState.other,
    },
    clock: safe<String?>(() => header!['status']['type']['shortDetail'] as String?) ?? '',
    homeScore: int.tryParse('${competitor('home')?['score'] ?? ''}'),
    awayScore: int.tryParse('${competitor('away')?['score'] ?? ''}'),
    shots: shots,
    statValues: statValues,
    statNames: [for (final s in hs) if (s is Map) '${s['name'] ?? ''}'],
    attendance: safe<int?>(() => (json['gameInfo']['attendance'] as num?)?.toInt()),
  );
}

/// A commentary play as a [Shot], or null when it isn't one or has no position.
Shot? _shot(Map p, String homeName) {
  final type = '${p['type']?['type'] ?? ''}';
  final x = (p['fieldPositionX'] as num?)?.toDouble(), y = (p['fieldPositionY'] as num?)?.toDouble();
  if (x == null || y == null || type == 'own-goal') return null;
  final ShotKind kind;
  if (type.startsWith('goal') || type == 'penalty---scored') {
    kind = ShotKind.goal;
  } else if (type == 'shot-on-target' || type == 'penalty---saved') {
    kind = ShotKind.onTarget;
  } else if (type == 'shot-blocked') {
    kind = ShotKind.blocked;
  } else if (type == 'shot-off-target' || type == 'penalty---missed' || type.contains('woodwork') || type.contains('post')) {
    kind = ShotKind.offTarget;
  } else {
    return null;
  }
  final team = '${p['team']?['displayName'] ?? ''}';
  return Shot(
    side: team == homeName ? 'home' : 'away',
    kind: kind,
    x: x,
    y: y,
    goalY: (p['goalPositionY'] as num?)?.toDouble(),
    endX: (p['fieldPosition2X'] as num?)?.toDouble(),
    endY: (p['fieldPosition2Y'] as num?)?.toDouble(),
    clock: '${p['clock']?['displayValue'] ?? ''}',
    player: _try(() => '${(p['participants'] as List).first['athlete']['displayName']}') ?? '',
    text: '${p['text'] ?? ''}',
  );
}

T? _try<T>(T Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
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
