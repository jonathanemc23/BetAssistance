import '../data/fixtures.dart';
import '../data/parlay.dart';
import 'assistant.dart';

/// Checks a parlay and explains each selection. The beta ships
/// [DataParlayChecker], which uses the ESPN match data the app already loads.
/// An AI-backed checker (for example the Claude API with the user's own key,
/// with web search) can implement the same interface later.
abstract class ParlayChecker {
  Future<ParlayCheck> check(Parlay parlay);
}

class DataParlayChecker implements ParlayChecker {
  DataParlayChecker(this.api, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final FixturesApi api;
  final DateTime Function() _now;

  @override
  Future<ParlayCheck> check(Parlay parlay) async {
    final now = _now();
    final legs = <LegCheck>[];
    // Chance of each leg: the market's (margin removed) where we have it,
    // otherwise the one implied by the user's price.
    final chances = <double>[];
    for (final leg in parlay.legs) {
      final (check, fair) = await _leg(leg, now);
      legs.add(check);
      chances.add(fair ?? 1 / leg.odds);
    }

    final summary = <String>[];
    final odds = parlay.odds;
    final chance = chances.fold(1.0, (a, c) => a * c);
    summary.add('${parlay.legs.length} selections at combined odds ${_price(odds)}.');
    summary.add('Estimated chance that every leg wins: ${_pct(chance)} '
        '(the price alone implies ${_pct(1 / odds)}).');
    final value = chance * odds - 1;
    summary.add(value >= 0
        ? 'On these numbers the price is fair or better (${_signed(value)} expected per unit staked).'
        : 'Expected return is ${_signed(value)} per unit staked, as usual for parlays; '
            'each extra leg adds the bookmaker margin again.');
    if (chances.isNotEmpty) {
      var weakest = 0;
      for (var i = 1; i < chances.length; i++) {
        if (chances[i] < chances[weakest]) weakest = i;
      }
      summary.add('Weakest leg: ${parlay.legs[weakest].selection} (${_pct(chances[weakest])}).');
    }
    final repeated = <String>{};
    final seen = <String>{};
    for (final l in parlay.legs) {
      final key = l.matchId ?? l.event.toLowerCase().trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) repeated.add(l.event.isEmpty ? l.selection : l.event);
    }
    for (final e in repeated) {
      summary.add('Two picks from $e: they win or lose together and many bookmakers won\'t combine them.');
    }
    final risk = parlay.legs.length >= 6 || odds > 10 || chance < 0.1
        ? 'High'
        : parlay.legs.length >= 4 || odds > 4 || chance < 0.25
            ? 'Medium'
            : 'Low';
    summary.add('This is a reading of the data, not a guarantee.');
    return ParlayCheck(checked: now.toIso8601String(), risk: risk, summary: summary, legs: legs);
  }

  /// The check for one leg, plus the market's chance for it when known.
  Future<(LegCheck, double?)> _leg(ParlayLeg leg, DateTime now) async {
    final lines = <String>['Price ${_price(leg.odds)} implies ${_pct(1 / leg.odds)}.'];
    if (leg.odds >= 3) lines.add('Long shot: this leg carries most of the risk.');
    final match = leg.toMatch();
    if (match == null) {
      lines.add('Added by hand, so only the price is checked.');
      return (LegCheck(selection: leg.selection, verdict: 'Price only', tone: LegTone.neutral, lines: lines), null);
    }
    if (leg.kickoff != null && leg.kickoff!.isBefore(now.toUtc())) {
      lines.add('Kick-off has passed: check the result and mark the leg.');
    }
    final MatchDetails d;
    try {
      d = await api.details(match);
    } catch (_) {
      lines.add("Couldn't load the match data right now.");
      return (LegCheck(selection: leg.selection, verdict: 'Price only', tone: LegTone.neutral, lines: lines), null);
    }

    final fair = _fairChance(leg, match, d);
    var verdict = 'No market data', tone = LegTone.neutral;
    if (fair != null) {
      final edge = leg.odds * fair - 1;
      lines.add('Market chance ${_pct(fair)}, fair price ${_price(1 / fair)}.');
      (verdict, tone) = edge >= 0.03
          ? ('Good price', LegTone.good)
          : edge >= -0.03
              ? ('Fair price', LegTone.neutral)
              : ('Below market', LegTone.warning);
    }
    lines.addAll(_context(leg, match, d));
    return (LegCheck(selection: leg.selection, verdict: verdict, tone: tone, lines: lines), fair);
  }

  /// The market's chance of [leg], from the best prices with the margin removed.
  static double? _fairChance(ParlayLeg leg, Match m, MatchDetails d) {
    final s = leg.selection.toLowerCase().trim();
    final total = RegExp(r'^(over|under) (\d+(?:\.\d+)?)').firstMatch(s);
    if (total != null) {
      final line = double.parse(total.group(2)!);
      final books = d.odds.isNotEmpty ? d.odds : [if (m.odds != null) m.odds!];
      final o = books.where((b) => b.totalLine == line && b.over != null && b.under != null).firstOrNull;
      if (o == null) return null;
      final over = 1 / o.over!, under = 1 / o.under!;
      return (total.group(1) == 'over' ? over : under) / (over + under);
    }
    final b = DataAssistant.bestOdds(m, d);
    if (b == null) return null;
    final sum = 1 + b.margin;
    final ph = 1 / b.home! / sum, pa = 1 / b.away! / sum, px = b.draw == null ? 0.0 : 1 / b.draw! / sum;
    final home = m.home.name.toLowerCase(), away = m.away.name.toLowerCase();
    return switch (s) {
      'draw' => b.draw == null ? null : px,
      _ when s == '$home to win' || s == home => ph,
      _ when s == '$away to win' || s == away => pa,
      _ when s == '$home or draw' => ph + px,
      _ when s == '$away or draw' => pa + px,
      _ when s == '$home or $away' => ph + pa,
      _ => null,
    };
  }

  /// Form and goals lines that matter for this kind of pick.
  static List<String> _context(ParlayLeg leg, Match m, MatchDetails d) {
    final s = leg.selection.toLowerCase();
    final out = <String>[];
    String form(String name, TeamInfo t) {
      final r = DataAssistant.recentOf(t);
      final pos = DataAssistant.positionOf(d, t);
      if (r.games == 0 && pos == null) return '';
      return '$name: ${r.games > 0 ? '${r.w * 3 + r.dr} pts from last ${r.games}' : ''}'
          '${r.games > 0 && pos != null ? ', ' : ''}${pos != null ? '${pos.$1} in the table' : ''}.';
    }

    if (s.startsWith('over') || s.startsWith('under')) {
      final h = DataAssistant.recentOf(d.home), a = DataAssistant.recentOf(d.away);
      final games = h.games + a.games;
      if (games > 0) {
        out.add('Over 2.5 in ${h.over25 + a.over25}/$games recent games of both teams; '
            '${((h.gf + h.ga + a.gf + a.ga) / games).toStringAsFixed(1)} goals a game.');
      }
    } else {
      final home = s.contains(m.home.name.toLowerCase()), away = s.contains(m.away.name.toLowerCase());
      if (home || !away) out.add(form(m.home.name, d.home));
      if (away || !home) out.add(form(m.away.name, d.away));
    }
    if (d.h2hSummary.isNotEmpty) out.add('Head to head: ${d.h2hSummary}.');
    return out.where((l) => l.isNotEmpty).toList();
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(v < 0.1 ? 1 : 0)}%';
  static String _price(double v) => v.toStringAsFixed(2);
  static String _signed(double v) => '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(0)}%';
}
