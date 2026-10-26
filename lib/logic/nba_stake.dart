import 'dart:convert';
import 'dart:math' as math;

import '../data/models.dart';
import '../l10n/l10n.dart';

/// Pro stakes: two or three NBA player lines ("20+ points: Kevin Durant")
/// from the day's games, bought with tokens in the Stake builder. For now
/// the lines are picked at random among each team's leaders, with a line
/// under the player's average so the price makes sense; the model gets
/// sharper later.

/// What a pro stake costs.
const proStakeCost = 6;

/// The total odds a pro stake lands between.
const proStakeMinOdds = 2.4, proStakeMaxOdds = 3.7;

/// The player stats a line can be on.
enum PropStat {
  points('points', 'PTS', 8, 5),
  rebounds('rebounds', 'REB', 4, 2),
  assists('assists', 'AST', 3, 2),
  threes('threes', '3PT', 1.5, 1);

  const PropStat(this.key, this.boxName, this.minAverage, this.minLine);
  final String key;

  /// The column in ESPN's box score.
  final String boxName;

  /// Players averaging less aren't picked for this stat.
  final double minAverage;
  final int minLine;

  /// "20+ points", in the app's language.
  String line(int n) => switch (this) {
        PropStat.points => tr('{n}+ points', {'n': n}),
        PropStat.rebounds => tr('{n}+ rebounds', {'n': n}),
        PropStat.assists => tr('{n}+ assists', {'n': n}),
        PropStat.threes => tr('{n}+ threes', {'n': n}),
      };

  /// [line] in English, as a logged bet saves it.
  String englishLine(int n) => '$n+ $key';

  static PropStat? byKey(String? k) => PropStat.values.where((s) => s.key == k).firstOrNull;
}

/// A team leader as ESPN's scoreboard lists them before a game: the season
/// average in one stat.
class NbaLeader {
  const NbaLeader(this.id, this.name, this.team, this.stat, this.average);
  final String id, name, team;
  final PropStat stat;
  final double average;
}

/// One game of the day, with each team's leaders.
class NbaGame {
  const NbaGame({
    required this.id,
    required this.home,
    required this.away,
    required this.tipoff,
    required this.scheduled,
    this.leaders = const [],
  });
  final String id, home, away;
  final DateTime tipoff; // UTC
  final bool scheduled;
  final List<NbaLeader> leaders;

  String get title => '$home vs $away';
}

/// The games in an ESPN NBA scoreboard response, with their leaders.
List<NbaGame> parseNbaScoreboard(String body) {
  final out = <NbaGame>[];
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    for (final e in (j['events'] as List? ?? const [])) {
      try {
        final c = ((e as Map)['competitions'] as List).first as Map;
        final state = '${(((c['status'] as Map?)?['type'] as Map?)?['state']) ?? ''}';
        String? home, away;
        final leaders = <NbaLeader>[];
        for (final t in (c['competitors'] as List? ?? const [])) {
          final team = '${((t as Map)['team'] as Map)['displayName']}';
          if (t['homeAway'] == 'home') {
            home = team;
          } else {
            away = team;
          }
          for (final l in (t['leaders'] as List? ?? const [])) {
            final stat = switch ((l as Map)['name']) {
              'pointsPerGame' => PropStat.points,
              'reboundsPerGame' => PropStat.rebounds,
              'assistsPerGame' => PropStat.assists,
              'threePointFieldGoalsMade' || 'threePointersPerGame' => PropStat.threes,
              _ => null,
            };
            final top = (l['leaders'] as List? ?? const []).firstOrNull as Map?;
            final athlete = top?['athlete'] as Map?;
            final avg = double.tryParse('${top?['displayValue'] ?? top?['value'] ?? ''}');
            if (stat == null || athlete == null || avg == null) continue;
            leaders.add(NbaLeader('${athlete['id']}', '${athlete['displayName']}', team, stat, avg));
          }
        }
        if (home == null || away == null) continue;
        out.add(NbaGame(
          id: '${e['id']}',
          home: home,
          away: away,
          tipoff: DateTime.parse('${e['date']}').toUtc(),
          scheduled: state == 'pre',
          leaders: leaders,
        ));
      } catch (_) {
        // A malformed event is skipped.
      }
    }
  } catch (_) {}
  return out;
}

/// A finished game's box score: each player's stats by name, lower case.
class NbaBoxScore {
  const NbaBoxScore({required this.finished, required this.players, this.didNotPlay = const {}});
  final bool finished;
  final Map<String, Map<PropStat, int>> players;

  /// Players listed who didn't play.
  final Set<String> didNotPlay;

  static String key(String name) => name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  int? stat(String player, PropStat s) => players[key(player)]?[s];
  bool listed(String player) => players.containsKey(key(player)) || didNotPlay.contains(key(player));
}

/// The box score in an ESPN NBA summary response.
NbaBoxScore parseNbaBoxScore(String body) {
  final players = <String, Map<PropStat, int>>{};
  final dnp = <String>{};
  var finished = false;
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final comp = (((j['header'] as Map?)?['competitions'] as List?)?.firstOrNull as Map?);
    finished = '${((comp?['status'] as Map?)?['type'] as Map?)?['state'] ?? ''}' == 'post';
    for (final team in ((j['boxscore'] as Map?)?['players'] as List? ?? const [])) {
      for (final group in ((team as Map)['statistics'] as List? ?? const [])) {
        final names = [for (final n in ((group as Map)['names'] as List? ?? const [])) '$n'];
        for (final a in (group['athletes'] as List? ?? const [])) {
          final name = NbaBoxScore.key('${((a as Map)['athlete'] as Map?)?['displayName'] ?? ''}');
          final stats = [for (final v in (a['stats'] as List? ?? const [])) '$v'];
          if (a['didNotPlay'] == true || stats.isEmpty) {
            dnp.add(name);
            continue;
          }
          int? read(String col) {
            final i = names.indexOf(col);
            if (i < 0 || i >= stats.length) return null;
            return int.tryParse(stats[i].split('-').first);
          }

          players[name] = {for (final s in PropStat.values) s: ?read(s.boxName)};
        }
      }
    }
  } catch (_) {}
  return NbaBoxScore(finished: finished, players: players, didNotPlay: dnp);
}

/// One line of a pro stake.
class NbaProp {
  const NbaProp({
    required this.gameId,
    required this.home,
    required this.away,
    required this.tipoff,
    required this.player,
    required this.team,
    required this.stat,
    required this.line,
    required this.odds,
    this.status = BetStatus.pending,
  });
  final String gameId, home, away, player, team;
  final DateTime tipoff; // UTC
  final PropStat stat;
  final int line;
  final double odds;
  final BetStatus status;

  String get matchTitle => '$home vs $away';

  /// "20+ points: Kevin Durant", in the app's language.
  String get label => '${stat.line(line)}: $player';

  /// The same in English, as a logged bet saves it and [parsePropPick] reads it.
  String get selection => '${stat.englishLine(line)}: $player';

  /// Won, lost, or void when the player didn't play; null until the game is over.
  BetStatus? grade(NbaBoxScore box) => gradeProp(stat, line, player, box);

  NbaProp withStatus(BetStatus s) => NbaProp(
      gameId: gameId, home: home, away: away, tipoff: tipoff, player: player, team: team, stat: stat, line: line,
      odds: odds, status: s);

  BetLeg toBetLeg() => BetLeg(
        selection: selection,
        event: matchTitle,
        sport: 'Basketball',
        odds: odds,
        status: status,
        matchId: gameId,
        leagueSlug: 'nba',
        leagueName: 'NBA',
        kickoff: tipoff,
      );

  Map<String, Object?> toJson() => {
        'game': gameId,
        'home': home,
        'away': away,
        'tipoff': tipoff.toIso8601String(),
        'player': player,
        'team': team,
        'stat': stat.key,
        'line': line,
        'odds': odds,
        'status': status.dbValue,
      };

  static NbaProp? fromJson(Object? j) {
    if (j is! Map) return null;
    final stat = PropStat.byKey(j['stat'] as String?);
    final tipoff = DateTime.tryParse('${j['tipoff']}');
    if (stat == null || tipoff == null) return null;
    return NbaProp(
      gameId: '${j['game']}',
      home: '${j['home'] ?? ''}',
      away: '${j['away'] ?? ''}',
      tipoff: tipoff.toUtc(),
      player: '${j['player'] ?? ''}',
      team: '${j['team'] ?? ''}',
      stat: stat,
      line: (j['line'] as num?)?.toInt() ?? 1,
      odds: (j['odds'] as num?)?.toDouble() ?? 1,
      status: BetStatusX.parse('${j['status'] ?? 'pending'}'),
    );
  }
}

/// Grades a player line from a box score: null while the game isn't over or
/// the player isn't in it yet, void when they didn't play.
BetStatus? gradeProp(PropStat stat, int line, String player, NbaBoxScore box) {
  if (!box.finished) return null;
  final v = box.stat(player, stat);
  if (v == null) return box.listed(player) || box.players.isNotEmpty ? BetStatus.voided : null;
  return v >= line ? BetStatus.won : BetStatus.lost;
}

/// A player line in a bet's selection: "20+ points: Kevin Durant" (as pro
/// stakes save it) or "Kevin Durant 20+ points". Null for anything else.
(PropStat, int, String)? parsePropPick(String selection) {
  final s = selection.trim();
  final a = RegExp(r'^(\d+)\+\s*(points|rebounds|assists|threes)\s*:\s*(.+)$', caseSensitive: false).firstMatch(s);
  if (a != null) return (PropStat.byKey(a[2]!.toLowerCase())!, int.parse(a[1]!), a[3]!.trim());
  final b = RegExp(r'^(.+?)\s+(\d+)\+\s*(points|rebounds|assists|threes)$', caseSensitive: false).firstMatch(s);
  if (b != null) return (PropStat.byKey(b[3]!.toLowerCase())!, int.parse(b[2]!), b[1]!.trim());
  return null;
}

/// A pro stake bought by the user.
class ProStake {
  const ProStake({required this.id, required this.created, required this.legs, this.cost = proStakeCost});
  final String id;
  final DateTime created;
  final List<NbaProp> legs;
  final int cost;

  double get odds => legs.where((l) => l.status != BetStatus.voided).fold(1.0, (a, l) => a * l.odds);
  BetStatus get status => parlayStatus([for (final l in legs) BetLeg(selection: '', odds: l.odds, status: l.status)]);
  int get finished => legs.where((l) => l.status != BetStatus.pending).length;

  /// "Double" or "Triple", as a bookmaker names it.
  String get kind => legs.length == 3 ? tr('Triple') : tr('Double');

  ProStake withLegs(List<NbaProp> next) => ProStake(id: id, created: created, legs: next, cost: cost);

  /// The stake as a parlay for the bet form, its legs tied to their games.
  Bet toBet({required double stake}) => Bet(
        type: BetType.parlay,
        selection: '${legs.length}-leg parlay',
        sport: 'Basketball',
        date: isoDate(legs.first.tipoff.toLocal()),
        stake: stake,
        odds: double.parse(odds.toStringAsFixed(4)),
        created: DateTime.now().toIso8601String(),
        notes: 'NBA pro tip',
        market: 'parlay',
        legs: [for (final l in legs) l.toBetLeg().copyWith(status: BetStatus.pending)],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'cost': cost,
        'legs': [for (final l in legs) l.toJson()],
      };

  static ProStake? fromJson(Object? j) {
    if (j is! Map) return null;
    final legs = [for (final l in (j['legs'] as List? ?? const [])) ?NbaProp.fromJson(l)];
    final created = DateTime.tryParse('${j['created']}');
    if (legs.isEmpty || created == null) return null;
    return ProStake(id: '${j['id']}', created: created, legs: legs, cost: (j['cost'] as num?)?.toInt() ?? proStakeCost);
  }
}

/// The games a pro stake can be built from at [now]: not started, with leaders.
List<NbaGame> openGames(List<NbaGame> games, DateTime now) =>
    [for (final g in games) if (g.scheduled && g.tipoff.isAfter(now) && g.leaders.isNotEmpty) g];

/// A line for [l] at about [odds]: the lower the price, the further under
/// the player's average the line sits.
int lineFor(NbaLeader l, double odds) {
  // The chance the price stands for, after a bookmaker's margin.
  final chance = (1.05 / odds).clamp(0.35, 0.9);
  final ratio = 1.22 - 0.75 * chance; // 0.9 chance -> 55% of the average, 50% -> 85%
  return math.max(l.stat.minLine, (l.average * ratio).floor());
}

/// Builds a pro stake from the games still to start at [now]: two or three
/// lines on different players (on different games when there are enough),
/// with total odds between [proStakeMinOdds] and [proStakeMaxOdds]. Null when
/// no game is left to start or none has enough leaders.
ProStake? generateProStake(List<NbaGame> games, DateTime now, math.Random rng) {
  final open = openGames(games, now);
  final candidates = [
    for (final g in open)
      for (final l in g.leaders)
        if (l.average >= l.stat.minAverage) (g, l),
  ];
  final players = {for (final (_, l) in candidates) l.name};
  if (players.length < 2) return null;
  final n = players.length >= 3 && rng.nextBool() ? 3 : 2;

  // Different games first, then different players.
  final pool = [...candidates]..shuffle(rng);
  final picked = <(NbaGame, NbaLeader)>[];
  for (final c in pool) {
    if (picked.length == n) break;
    if (picked.any((p) => p.$1.id == c.$1.id || p.$2.name == c.$2.name)) continue;
    picked.add(c);
  }
  for (final c in pool) {
    if (picked.length == n) break;
    if (picked.any((p) => p.$2.name == c.$2.name)) continue;
    picked.add(c);
  }

  // A total in the range, split about evenly across the legs.
  final target = 2.55 + rng.nextDouble() * 1.0;
  final each = math.pow(target, 1 / n).toDouble();
  final odds = [for (var i = 0; i < n; i++) _round2(each * (0.94 + rng.nextDouble() * 0.12))];
  var total = odds.fold(1.0, (a, o) => a * o);
  if (total < proStakeMinOdds || total > proStakeMaxOdds) {
    odds[n - 1] = _round2(odds[n - 1] * target / total);
    total = odds.fold(1.0, (a, o) => a * o);
  }

  final legs = [
    for (final (i, (g, l)) in picked.indexed)
      NbaProp(
        gameId: g.id,
        home: g.home,
        away: g.away,
        tipoff: g.tipoff,
        player: l.name,
        team: l.team,
        stat: l.stat,
        line: lineFor(l, odds[i]),
        odds: odds[i],
      ),
  ]..sort((a, b) => a.tipoff.compareTo(b.tipoff));
  return ProStake(id: 'pro:${now.toUtc().toIso8601String()}', created: now, legs: legs);
}

double _round2(double v) => (v * 100).round() / 100;
