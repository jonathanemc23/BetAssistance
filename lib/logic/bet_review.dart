import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import 'assistant.dart';
import 'markets.dart';
import 'stats.dart';

/// A review of one bet: short sections the Review bet page shows in order.
class BetReview {
  const BetReview({required this.headline, required this.sections, this.suggestedResult, this.match});
  final String headline;
  final List<ReviewSection> sections;

  /// Set when the match is over and the pick can be graded from the score.
  final BetStatus? suggestedResult;

  /// The match the bet was found on, if any.
  final Match? match;
}

enum ReviewTone { good, neutral, warning }

class ReviewSection {
  const ReviewSection(this.kind, this.title, this.lines, {this.tone = ReviewTone.neutral});

  /// One of: bet, updates, market, context, suggestions, record.
  final String kind;
  final String title;
  final List<String> lines;
  final ReviewTone tone;
}

/// Reviews a bet. The beta ships [DataBetReviewer], which uses the ESPN data
/// the app already loads and the user's own history. An AI-backed reviewer
/// (with web search) can implement the same interface later.
abstract class BetReviewer {
  Future<BetReview> review(Bet bet, {required List<Bet> history, required Stats stats, required Settings settings});
}

class DataBetReviewer implements BetReviewer {
  DataBetReviewer(this.api, {this.country, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final FixturesApi api;

  /// Where to look for the match when the bet wasn't picked from the list.
  final Country? country;
  final DateTime Function() _now;

  @override
  Future<BetReview> review(
    Bet bet, {
    required List<Bet> history,
    required Stats stats,
    required Settings settings,
  }) async {
    final currency = NumberFormat.simpleCurrency(name: settings.currency);
    String money(double v) => currency.format(v);
    final market = bet.isParlay ? 'parlay' : (bet.market.isNotEmpty ? bet.market : marketOf(bet.selection));
    final sections = <ReviewSection>[];
    final suggestions = <String>[];
    var good = 0, warn = 0;

    // ---------------------------------------------------------- The bet
    final o = bet.odds;
    sections.add(
      ReviewSection('bet', 'Your bet', [
        bet.isParlay
            ? '${bet.legs.length}-leg parlay at combined odds ${_price(o)}.'
            : '${bet.selection}${bet.event.isEmpty ? '' : ' in ${bet.event}'} at ${_price(o)}.',
        'The price implies a ${_pct(1 / o)} chance. Stake ${money(bet.stake)} to return ${money(bet.stake * o)}.',
        'Market: ${market == 'parlay' ? 'Parlay' : marketById(market).label}. Status: ${bet.status.label}.',
      ]),
    );

    // ---------------------------------------------------------- Match data
    Match? match;
    MatchDetails? d;
    if (!bet.isParlay) {
      match = await _findMatch(bet);
      if (match != null) {
        try {
          d = await api.details(match);
        } catch (_) {}
      }
    }

    BetStatus? suggested;
    double? fair;
    if (match != null && d != null) {
      final m = match;
      final home = m.home.name, away = m.away.name;
      final updates = <String>[];
      final hs = d.homeScore ?? int.tryParse(m.home.score ?? ''), as = d.awayScore ?? int.tryParse(m.away.score ?? '');
      final state = d.state != MatchState.other ? d.state : m.state;
      switch (state) {
        case MatchState.live:
          updates.add('Live now: $home ${hs ?? 0}-${as ?? 0} $away${d.clock.isEmpty ? '' : ' (${d.clock})'}.');
        case MatchState.finished:
          updates.add('Full time: $home ${hs ?? '?'}-${as ?? '?'} $away.');
        case MatchState.scheduled:
          updates.add('Not started yet: kick-off ${_when(m.kickoff)}.');
        case MatchState.other:
          if (d.clock.isNotEmpty) updates.add('Status: ${d.clock}.');
      }
      if (hs != null && as != null && state != MatchState.scheduled) {
        final r = gradePick(market, bet.selection, home, away, hs, as);
        if (r != null) {
          if (state == MatchState.finished) {
            updates.add(
              'On this score the pick is ${r == BetStatus.won
                  ? 'won'
                  : r == BetStatus.lost
                  ? 'lost'
                  : 'a push (stake back)'}.',
            );
            if (bet.status == BetStatus.pending) suggested = r;
          } else {
            updates.add(
              'On the current score the pick would be ${r == BetStatus.won
                  ? 'winning'
                  : r == BetStatus.lost
                  ? 'losing'
                  : 'level (stake back)'}.',
            );
          }
        }
      }
      final created = DateTime.tryParse(bet.created);
      final fresh = [
        for (final n in d.news)
          if (created == null || n.published == null || n.published!.isAfter(created)) n,
      ];
      for (final n in fresh.take(3)) {
        updates.add('News: ${n.headline}');
      }
      if (d.home.starters.isNotEmpty || d.away.starters.isNotEmpty) {
        updates.add(
          'Line-ups are out: $home ${d.home.formation ?? ''}, $away ${d.away.formation ?? ''}.'.replaceAll(' ,', ','),
        );
      }
      sections.add(ReviewSection('updates', 'Since you placed it', updates));

      // Price now against the price taken.
      final now = _currentPrice(market, bet.selection, m, d);
      if (now != null) {
        fair = now.fair;
        final lines = <String>[
          'Best price now ${_price(now.best)} (market chance ${_pct(now.fair)}, fair price ${_price(1 / now.fair)}).',
        ];
        final edge = o * now.fair - 1;
        var tone = ReviewTone.neutral;
        if (o > now.best * 1.02) {
          lines.add(
            'You took ${_price(o)}, better than the price now: you beat the market by ${_pct(o / now.best - 1)}.',
          );
          tone = ReviewTone.good;
          good++;
        } else if (o < now.best * 0.98) {
          lines.add(
            'The price has drifted to ${_price(now.best)}: the same bet is worth more now, so the market rates it lower than when you placed it.',
          );
          tone = ReviewTone.warning;
        }
        if (edge >= 0.03) {
          lines.add('Your price is above fair value (${_signed(edge)} expected).');
          tone = ReviewTone.good;
          good++;
        } else if (edge <= -0.05) {
          lines.add(
            'Your price is below fair value (${_signed(edge)} expected). Shopping around for a better price helps.',
          );
          tone = ReviewTone.warning;
          warn++;
        }
        sections.add(ReviewSection('market', 'Price check', lines, tone: tone));
      }

      // Form, table and head to head for the teams in the pick.
      final ctx = <String>[];
      for (final (name, t) in [(home, d.home), (away, d.away)]) {
        final r = DataAssistant.recentOf(t);
        final pos = DataAssistant.positionOf(d, t);
        if (r.games == 0 && pos == null) continue;
        ctx.add(
          '$name: ${r.games > 0 ? '${t.form.isEmpty ? '' : '${t.form} · '}${r.w * 3 + r.dr} pts from last ${r.games}, goals ${r.gf}-${r.ga}' : ''}'
          '${r.games > 0 && pos != null ? '; ' : ''}${pos != null ? '${pos.$1} in the table' : ''}.',
        );
      }
      if (const {'goals', 'btts', 'corners', 'cards'}.contains(market)) {
        final h = DataAssistant.recentOf(d.home), a = DataAssistant.recentOf(d.away);
        final games = h.games + a.games;
        if (games > 0) {
          ctx.add(
            'Recent games: over 2.5 goals in ${h.over25 + a.over25}/$games, both scored in ${h.btts + a.btts}/$games.',
          );
        }
      }
      if (d.h2hSummary.isNotEmpty) ctx.add('Head to head: ${d.h2hSummary}.');
      if (ctx.isNotEmpty) sections.add(ReviewSection('context', 'Form and context', ctx));
    } else if (!bet.isParlay && bet.sport == 'Soccer') {
      sections.add(
        const ReviewSection('updates', 'Since you placed it', [
          "Couldn't match this bet to a listed match, so there's no live data. Bets picked from Matches are linked automatically.",
        ]),
      );
    }

    // ---------------------------------------------------------- Suggestions
    final unit = settings.unit;
    if (unit > 0 && bet.stake > unit * 2) {
      suggestions.add(
        'This stake is ${(bet.stake / unit).toStringAsFixed(1)} units, above your usual ${money(unit)}. Keep bigger stakes for picks with a clear edge.',
      );
      warn++;
    }
    final bank = stats.balance;
    if (bank > 0 && bet.stake / bank > 0.05) {
      suggestions.add(
        'This bet is ${_pct(bet.stake / bank)} of your bankroll. Most staking plans stay at 1-3% per bet.',
      );
      warn++;
    }
    if (bet.isParlay) {
      if (bet.legs.length >= 4) {
        suggestions.add(
          '${bet.legs.length} legs: every extra leg adds the bookmaker margin again. Fewer, stronger legs usually pay off better.',
        );
        warn++;
      }
      final open = bet.legs.where((l) => l.status == BetStatus.pending).length;
      final lost = bet.legs.where((l) => l.status == BetStatus.lost).length;
      if (lost > 0) {
        suggestions.add('$lost leg${lost == 1 ? '' : 's'} already lost, so the parlay is lost.');
      } else if (open > 0 && open < bet.legs.length) {
        suggestions.add(
          '${bet.legs.length - open} legs in, $open to go. If your bookmaker offers a cash out, compare it with the ${_pct(1 / bet.legs.where((l) => l.status == BetStatus.pending).fold(1.0, (a, l) => a * l.odds))} chance the rest come in.',
        );
      }
    }
    if (o >= 3) suggestions.add('Long shot: expect to lose most bets like this. Keep stakes small on high odds.');
    if (o <= 1.3) suggestions.add('Short price: you risk a lot to win a little, so one loss wipes out several wins.');
    if (suggested != null) {
      suggestions.add(
        'The match is over. Mark the bet as ${suggested.label.toLowerCase()} to keep your bankroll right.',
      );
    } else if (bet.status == BetStatus.pending &&
        match != null &&
        match.kickoff.isAfter(_now().toUtc()) &&
        d != null &&
        d.home.starters.isEmpty) {
      suggestions.add('Line-ups are not out yet. Check them before kick-off in case a key player is missing.');
    }
    if (bet.status == BetStatus.lost && fair != null && o * fair < 1) {
      suggestions.add('The price was below fair value, so this bet was a long-term loser even before the result.');
    }
    if (suggestions.isEmpty)
      suggestions.add('Nothing stands out: the stake and the price look in line with your usual bets.');
    sections.add(
      ReviewSection('suggestions', 'Suggestions', suggestions, tone: warn > 0 ? ReviewTone.warning : ReviewTone.good),
    );

    // ---------------------------------------------------------- Track record
    final record = <String>[];
    String line(String label, Iterable<Bet> bets) {
      final graded = bets.where((b) => b.isSettled && b.id != bet.id).toList();
      if (graded.isEmpty) return '';
      final won = graded.where((b) => b.status == BetStatus.won).length;
      final lost = graded.where((b) => b.status == BetStatus.lost).length;
      final staked = graded.fold(0.0, (a, b) => a + b.stake);
      final profit = graded.fold(0.0, (a, b) => a + b.profit);
      return '$label: ${graded.length} settled, $won won, $lost lost, '
          '${staked > 0 ? 'ROI ${_signed(profit / staked)}' : 'no stake'}.';
    }

    record.add(
      line(
        market == 'parlay' ? 'Parlays' : marketById(market).label,
        history.where(
          (b) => (b.isParlay ? 'parlay' : (b.market.isNotEmpty ? b.market : marketOf(b.selection))) == market,
        ),
      ),
    );
    if (!bet.isParlay) record.add(line(bet.sport, history.where((b) => !b.isParlay && b.sport == bet.sport)));
    final band = o < 1.7
        ? (1.0, 1.7, 'under 1.70')
        : o < 2.5
        ? (1.7, 2.5, '1.70 to 2.50')
        : (2.5, 1000.0, '2.50 and up');
    record.add(line('Odds ${band.$3}', history.where((b) => b.odds >= band.$1 && b.odds < band.$2)));
    record.removeWhere((l) => l.isEmpty);
    if (record.isNotEmpty) sections.add(ReviewSection('record', 'Your record on similar bets', record));

    final headline = suggested != null
        ? 'Match over: this pick looks ${suggested.label.toLowerCase()}.'
        : warn > good
        ? 'A few things to watch on this bet.'
        : good > 0
        ? 'Good price on this bet.'
        : 'This bet looks in line with your usual play.';
    return BetReview(headline: headline, sections: sections, suggestedResult: suggested, match: match);
  }

  /// The match the bet was picked from, or one found by its teams and date.
  Future<Match?> _findMatch(Bet bet) async {
    if (bet.matchId != null && bet.leagueSlug != null) {
      final (h, a) = teamsOf(bet.event);
      return Match(
        id: bet.matchId!,
        league: League(bet.leagueSlug!, bet.leagueName ?? ''),
        kickoff: bet.kickoff ?? DateTime.tryParse(bet.date)?.toUtc() ?? _now().toUtc(),
        home: Team(h, h, null, null),
        away: Team(a, a, null, null),
        state: MatchState.other,
        detail: '',
      );
    }
    final c = country;
    final day = DateTime.tryParse(bet.date);
    if (c == null || day == null || bet.sport != 'Soccer') return null;
    final (h, a) = teamsOf(bet.event);
    if (h == 'Home') return null;
    try {
      final list = await api.matches(c, day);
      String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ ]'), '').trim();
      bool same(String x, String y) => n(x) == n(y) || n(x).contains(n(y)) || n(y).contains(n(x));
      return list.where((m) => same(m.home.name, h) && same(m.away.name, a)).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Best current price and the market's chance for the pick, when the feed has them.
  static ({double best, double fair})? _currentPrice(String market, String selection, Match m, MatchDetails d) {
    final s = selection.toLowerCase().trim();
    final books = d.odds.isNotEmpty ? d.odds : [if (m.odds != null) m.odds!];
    if (market == 'goals') {
      final t = RegExp(r'^(over|under) (\d+(?:\.\d+)?)').firstMatch(s);
      if (t == null) return null;
      final line = double.parse(t.group(2)!);
      final o = books.where((b) => b.totalLine == line && b.over != null && b.under != null).firstOrNull;
      if (o == null) return null;
      final over = t.group(1) == 'over';
      final po = 1 / o.over!, pu = 1 / o.under!;
      return (best: over ? o.over! : o.under!, fair: (over ? po : pu) / (po + pu));
    }
    final b = DataAssistant.bestOdds(m, d);
    if (b == null) return null;
    final sum = 1 + b.margin;
    final home = m.home.name.toLowerCase(), away = m.away.name.toLowerCase();
    if (market == 'result') {
      if (s == 'draw' && b.draw != null) return (best: b.draw!, fair: 1 / b.draw! / sum);
      if (s.startsWith(home)) return (best: b.home!, fair: 1 / b.home! / sum);
      if (s.startsWith(away)) return (best: b.away!, fair: 1 / b.away! / sum);
    }
    return null;
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(v.abs() < 0.1 ? 1 : 0)}%';
  static String _signed(double v) => '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(0)}%';
  static String _price(double v) => v.toStringAsFixed(2);
  static String _when(DateTime utc) {
    final l = utc.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

/// Grades a pick from a score: won, lost or push (stake back). Null when the
/// market can't be graded from the score alone (corners, cards, scorers...).
BetStatus? gradePick(String market, String selection, String home, String away, int hs, int as) {
  final s = selection.toLowerCase().trim();
  final h = home.toLowerCase(), a = away.toLowerCase();
  BetStatus win(bool w) => w ? BetStatus.won : BetStatus.lost;
  String? team() => s.startsWith(h)
      ? 'home'
      : s.startsWith(a)
      ? 'away'
      : null;
  switch (market) {
    case 'result':
      if (s == 'draw') return win(hs == as);
      return switch (team()) {
        'home' => win(hs > as),
        'away' => win(as > hs),
        _ => null,
      };
    case 'double_chance':
      final hasH = s.contains(h), hasA = s.contains(a), hasD = s.contains('draw');
      if (hasH && hasA) return win(hs != as);
      if (hasH && hasD) return win(hs >= as);
      if (hasA && hasD) return win(as >= hs);
      return null;
    case 'dnb':
      if (hs == as) return BetStatus.push;
      return switch (team()) {
        'home' => win(hs > as),
        'away' => win(as > hs),
        _ => null,
      };
    case 'handicap':
      final side = team();
      final line = double.tryParse(RegExp(r'([+-]?\d+(?:\.\d+)?)\s*$').firstMatch(s)?.group(1) ?? '');
      if (side == null || line == null || (line * 4).round() % 2 != 0) return null; // quarter lines: skip
      final diff = (side == 'home' ? hs - as : as - hs) + line;
      return diff == 0 ? BetStatus.push : win(diff > 0);
    case 'goals':
      final t = RegExp(r'^(over|under) (\d+(?:\.\d+)?)').firstMatch(s);
      if (t == null) return null;
      final line = double.parse(t.group(2)!), total = hs + as;
      if (total == line) return BetStatus.push;
      return win(t.group(1) == 'over' ? total > line : total < line);
    case 'btts':
      final both = hs > 0 && as > 0;
      return win(s.endsWith('no') ? !both : both);
    case 'correct_score':
      final sc = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(s);
      if (sc == null) return null;
      return win(int.parse(sc.group(1)!) == hs && int.parse(sc.group(2)!) == as);
  }
  return null;
}
