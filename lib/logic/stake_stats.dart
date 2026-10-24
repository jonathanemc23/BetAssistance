import 'dart:math' as math;

import '../data/fixtures.dart';
import '../l10n/l10n.dart';

/// The numbers the stake builder counts in a soccer match, with ESPN's name
/// for each in a game's box score. Goals come from the score.
enum StakeStat {
  goals(['']),
  corners(['wonCorners']),
  cards(['yellowCards', 'redCards']),
  shotsOnTarget(['shotsOnTarget']),
  shots(['totalShots']),
  fouls(['foulsCommitted']);

  const StakeStat(this.espn);
  final List<String> espn;

  /// The stat's plural noun, in the app's language ("corners").
  String get noun => switch (this) {
        goals => tr('goals'),
        corners => tr('corners'),
        cards => tr('cards'),
        shotsOnTarget => tr('shots on target'),
        shots => tr('shots'),
        fouls => tr('fouls'),
      };

  /// The heading of the stat's row ("Corners").
  String get title => switch (this) {
        goals => tr('Goals'),
        corners => tr('Corners'),
        cards => tr('Cards'),
        shotsOnTarget => tr('Shots on target'),
        shots => tr('Shots'),
        fouls => tr('Fouls'),
      };

  static StakeStat byName(String? n) => values.where((s) => s.name == n).firstOrNull ?? goals;
}

/// Whose number a pick counts: both teams together or one team's own.
enum StakeScope {
  match,
  home,
  away;

  static StakeScope byName(String? n) => values.where((s) => s.name == n).firstOrNull ?? match;
}

/// One team's numbers in one of its past games: what it made ([mine]) and
/// what the other side made ([theirs]).
class StatGame {
  const StatGame({
    required this.date,
    required this.opponent,
    required this.atHome,
    required this.goalsFor,
    required this.goalsAgainst,
    this.mine = const {},
    this.theirs = const {},
  });
  final DateTime? date;
  final String opponent;
  final bool atHome;
  final int goalsFor, goalsAgainst;
  final Map<StakeStat, int> mine, theirs;

  int? own(StakeStat s) => s == StakeStat.goals ? goalsFor : mine[s];
  int? allowed(StakeStat s) => s == StakeStat.goals ? goalsAgainst : theirs[s];
  int? total(StakeStat s) {
    final a = own(s), b = allowed(s);
    return a == null || b == null ? null : a + b;
  }

  /// "2-1", the team's goals first.
  String get score => '$goalsFor-$goalsAgainst';
}

int? _count(String raw) => int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '').trim());

/// The stats of one stat from a game's box score, as (home, away).
(int?, int?) statOf(MatchDetails d, StakeStat s) {
  if (s == StakeStat.goals) return (d.homeScore, d.awayScore);
  int? h, a;
  for (final key in s.espn) {
    final v = d.statValues[key];
    if (v == null) continue;
    final x = _count(v.$1), y = _count(v.$2);
    if (x != null) h = (h ?? 0) + x;
    if (y != null) a = (a ?? 0) + y;
  }
  return (h, a);
}

/// [teamId]'s numbers in a finished game's summary. Null when the team
/// didn't play in it or the game has no score.
StatGame? statGameOf(MatchDetails d, String teamId, {DateTime? date}) {
  final home = d.home.id == teamId;
  if (!home && d.away.id != teamId) return null;
  if (d.homeScore == null || d.awayScore == null) return null;
  final mine = <StakeStat, int>{}, theirs = <StakeStat, int>{};
  for (final s in StakeStat.values.skip(1)) {
    final (h, a) = statOf(d, s);
    if (h == null || a == null) continue;
    mine[s] = home ? h : a;
    theirs[s] = home ? a : h;
  }
  return StatGame(
    date: date,
    opponent: home ? d.away.name : d.home.name,
    atHome: home,
    goalsFor: home ? d.homeScore! : d.awayScore!,
    goalsAgainst: home ? d.awayScore! : d.homeScore!,
    mine: mine,
    theirs: theirs,
  );
}

/// One team's latest games, newest first.
class TeamForm {
  const TeamForm({required this.team, this.games = const []});
  final String team;
  final List<StatGame> games;

  double? _avg(Iterable<int?> xs) {
    final v = [for (final x in xs) ?x];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  /// What the team makes a game, on average.
  double? avgFor(StakeStat s) => _avg(games.map((g) => g.own(s)));

  /// What its opponents make a game, on average.
  double? avgAgainst(StakeStat s) => _avg(games.map((g) => g.allowed(s)));

  /// Both teams together, a game, on average.
  double? avgTotal(StakeStat s) => _avg(games.map((g) => g.total(s)));
}

/// Both teams' latest games, for the stake builder's stat rows.
class StakeStats {
  const StakeStats({required this.home, required this.away});
  final TeamForm home, away;

  bool get isEmpty => home.games.isEmpty && away.games.isEmpty;

  /// What the match should give: each side's average blended with what the
  /// other side allows.
  double? expected(StakeStat s, StakeScope scope) {
    double? blend(double? a, double? b) => a == null ? b : (b == null ? a : (a + b) / 2);
    final h = blend(home.avgFor(s), away.avgAgainst(s));
    final a = blend(away.avgFor(s), home.avgAgainst(s));
    return switch (scope) {
      StakeScope.home => h,
      StakeScope.away => a,
      StakeScope.match => h == null || a == null ? null : h + a,
    };
  }

  /// The past numbers a line is checked against: every game total of both
  /// teams for the match, else the team's own numbers and what the other
  /// team allowed.
  List<int> sample(StakeStat s, StakeScope scope) => switch (scope) {
        StakeScope.match => [
            for (final g in [...home.games, ...away.games]) ?g.total(s),
          ],
        StakeScope.home => [
            for (final g in home.games) ?g.own(s),
            for (final g in away.games) ?g.allowed(s),
          ],
        StakeScope.away => [
            for (final g in away.games) ?g.own(s),
            for (final g in home.games) ?g.allowed(s),
          ],
      };

  /// How often the line came in over those games, 0 to 1. Null with no
  /// games to count.
  double? hitRate(StakeStat s, StakeScope scope, {required bool over, required double line}) {
    final xs = sample(s, scope);
    if (xs.isEmpty) return null;
    return xs.where((x) => over ? x > line : x < line).length / xs.length;
  }

  /// Three lines around what the match should give: the one just under the
  /// expected number and one on each side of it.
  List<double> lines(StakeStat s, StakeScope scope) {
    final e = expected(s, scope);
    if (e == null) return const [];
    final mid = e.floor() + 0.5;
    return [for (final l in [mid - 1, mid, mid + 1]) if (l > 0) l];
  }
}

/// One stat a user put in their stake: the match, what it counts, which way
/// and the line, with the hit rate it had when it was added.
class StakePick {
  const StakePick({
    required this.matchId,
    required this.leagueSlug,
    required this.leagueName,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.stat,
    required this.scope,
    required this.over,
    required this.line,
    this.homeLogo,
    this.awayLogo,
    this.hitRate,
    this.average,
  });

  final String matchId, leagueSlug, leagueName, home, away;
  final String? homeLogo, awayLogo;
  final DateTime kickoff; // UTC
  final StakeStat stat;
  final StakeScope scope;
  final bool over;
  final double line;
  final double? hitRate, average;

  factory StakePick.of(Match m, StakeStats stats, StakeStat s, StakeScope scope, {required bool over, required double line}) =>
      StakePick(
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        homeLogo: m.home.logo,
        awayLogo: m.away.logo,
        kickoff: m.kickoff,
        stat: s,
        scope: scope,
        over: over,
        line: line,
        hitRate: stats.hitRate(s, scope, over: over, line: line),
        average: stats.expected(s, scope),
      );

  /// A stake holds one pick per match, stat and side: a new line replaces it.
  String get slot => '$matchId|${stat.name}|${scope.name}';

  String get team => switch (scope) {
        StakeScope.home => home,
        StakeScope.away => away,
        StakeScope.match => '',
      };

  /// "Over 9.5 corners", "Arsenal under 1.5 goals", in the app's language.
  String get label {
    final args = {'line': lineText(line), 'stat': stat.noun, 'team': team};
    if (scope == StakeScope.match) return over ? tr('Over {line} {stat}', args) : tr('Under {line} {stat}', args);
    return over ? tr('{team} over {line} {stat}', args) : tr('{team} under {line} {stat}', args);
  }

  String get matchTitle => '$home vs $away';

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

  Map<String, Object?> toJson() => {
        'match': matchId,
        'league': leagueSlug,
        'leagueName': leagueName,
        'home': home,
        'away': away,
        'homeLogo': homeLogo,
        'awayLogo': awayLogo,
        'kickoff': kickoff.toUtc().toIso8601String(),
        'stat': stat.name,
        'scope': scope.name,
        'over': over,
        'line': line,
        'hit': hitRate,
        'avg': average,
      };

  static StakePick? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return StakePick(
        matchId: j['match'] as String,
        leagueSlug: j['league'] as String,
        leagueName: j['leagueName'] as String? ?? '',
        home: j['home'] as String,
        away: j['away'] as String,
        homeLogo: j['homeLogo'] as String?,
        awayLogo: j['awayLogo'] as String?,
        kickoff: DateTime.parse(j['kickoff'] as String).toUtc(),
        stat: StakeStat.byName(j['stat'] as String?),
        scope: StakeScope.byName(j['scope'] as String?),
        over: j['over'] as bool? ?? true,
        line: (j['line'] as num).toDouble(),
        hitRate: (j['hit'] as num?)?.toDouble(),
        average: (j['avg'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// "9.5", "10".
String lineText(double l) => l == l.roundToDouble() ? '${l.round()}' : l.toStringAsFixed(1);

/// How a pick looks once checked: by the latest games before kick-off, by
/// the match itself once it's on.
enum PickVerdict {
  strong,
  fair,
  risky,
  noData,
  onTrack,
  behind,
  won,
  lost;

  String get title => switch (this) {
        strong => tr('Strong'),
        fair => tr('Fair'),
        risky => tr('Risky'),
        noData => tr('No data'),
        onTrack => tr('On track'),
        behind => tr('Behind'),
        won => tr('Won'),
        lost => tr('Lost'),
      };

  bool get good => this == strong || this == won || this == onTrack;
  bool get bad => this == risky || this == lost || this == behind;
}

/// One pick reviewed against its match.
class PickCheck {
  const PickCheck(this.pick, this.verdict, this.note, {this.actual, this.hitRate});
  final StakePick pick;
  final PickVerdict verdict;
  final String note;

  /// The match's number so far, once it has started.
  final int? actual;

  /// How often the line came in over the latest games.
  final double? hitRate;
}

String _pct(double r) => '${(r * 100).round()}%';

/// Reviews [p] against its match: by [result] once the match is live or
/// finished, else by how often the line came in over the teams' latest
/// games in [stats] (the hit rate saved with the pick when there are none).
PickCheck checkPick(StakePick p, {StakeStats? stats, MatchDetails? result}) {
  final state = result?.state;
  if (result != null && (state == MatchState.live || state == MatchState.finished)) {
    final (h, a) = statOf(result, p.stat);
    final actual = switch (p.scope) {
      StakeScope.match => h == null || a == null ? null : h + a,
      StakeScope.home => h,
      StakeScope.away => a,
    };
    if (actual != null) {
      final args = {'n': actual, 'stat': p.stat.noun, 'line': lineText(p.line)};
      if (state == MatchState.finished) {
        final won = p.over ? actual > p.line : actual < p.line;
        return PickCheck(p, won ? PickVerdict.won : PickVerdict.lost, tr('Finished with {n} {stat}.', args), actual: actual);
      }
      // Live: an over is settled once it's passed; an under until it is.
      if (p.over && actual > p.line) return PickCheck(p, PickVerdict.won, tr('{n} {stat} already: the line is passed.', args), actual: actual);
      if (!p.over && actual > p.line) return PickCheck(p, PickVerdict.lost, tr('{n} {stat} already: over the line.', args), actual: actual);
      return PickCheck(
        p,
        p.over ? PickVerdict.behind : PickVerdict.onTrack,
        tr('{n} {stat} so far, line {line}.', args),
        actual: actual,
      );
    }
  }
  final rate = stats?.hitRate(p.stat, p.scope, over: p.over, line: p.line) ?? p.hitRate;
  final games = stats?.sample(p.stat, p.scope).length ?? 0;
  final avg = stats?.expected(p.stat, p.scope) ?? p.average;
  if (rate == null) return PickCheck(p, PickVerdict.noData, tr('No recent games with this stat to check it against.'));
  // The average on the wrong side of the line takes a step off.
  final against = avg != null && (p.over ? avg < p.line : avg > p.line);
  var verdict = rate >= 0.7 ? PickVerdict.strong : (rate >= 0.55 ? PickVerdict.fair : PickVerdict.risky);
  if (against && verdict != PickVerdict.risky) verdict = PickVerdict.values[verdict.index + 1];
  final args = {
    'rate': _pct(rate),
    'n': games,
    'avg': avg == null ? '-' : avg.toStringAsFixed(1),
    'stat': p.stat.noun,
  };
  final note = games == 0
      ? tr('Came in {rate} of the time when it was added. Expected {avg} {stat}.', args)
      : tr('Came in {rate} of the last {n} games. Expected {avg} {stat}.', args);
  return PickCheck(p, verdict, note, hitRate: rate);
}

/// What the whole stake looks like once each pick is checked.
class StakeReview {
  const StakeReview(this.checks);
  final List<PickCheck> checks;

  bool get settled => checks.isNotEmpty && checks.every((c) => c.verdict == PickVerdict.won || c.verdict == PickVerdict.lost);
  bool get lost => checks.any((c) => c.verdict == PickVerdict.lost);

  /// The chance every pick comes in, the hit rates taken as independent.
  /// Null when a pick has no rate.
  double? get chance {
    var p = 1.0;
    for (final c in checks) {
      if (c.verdict == PickVerdict.won) continue;
      if (c.verdict == PickVerdict.lost) return 0;
      final r = c.hitRate;
      if (r == null) return null;
      p *= r;
    }
    return checks.isEmpty ? null : p;
  }

  /// The fair price of [chance], as decimal odds.
  double? get fairOdds {
    final c = chance;
    return c == null || c <= 0 ? null : math.max(1.01, 1 / c);
  }

  /// One line on the stake as a whole.
  String get summary {
    if (checks.isEmpty) return '';
    if (lost) return tr('A pick has lost: this stake is gone.');
    if (settled) return tr('Every pick came in.');
    final weak = checks.where((c) => c.verdict.bad).length;
    final c = chance;
    final odds = fairOdds;
    final head = c == null
        ? tr('Some picks have no data to check them against.')
        : tr('About {pct} chance that every pick comes in (fair odds {odds}).',
            {'pct': _pct(c), 'odds': odds == null ? '-' : odds.toStringAsFixed(2)});
    if (weak == 0) return head;
    return '$head ${trn(weak, '{n} pick looks weak: think about dropping it.', '{n} picks look weak: think about dropping them.')}';
  }
}
