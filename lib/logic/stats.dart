import '../data/models.dart';

class Stats {
  final double profit;
  final double turnover;
  final double roi;
  final double deposits;
  final double withdrawals;
  final double exposure;
  final int pendingCount;
  final int wins;
  final int losses;
  final int count;
  final int settledCount;
  final double winRate;
  final double avgOdds;
  final double balance;
  final double available;
  final double units;

  const Stats({
    required this.profit, required this.turnover, required this.roi, required this.deposits,
    required this.withdrawals, required this.exposure, required this.pendingCount, required this.wins,
    required this.losses, required this.count, required this.settledCount, required this.winRate,
    required this.avgOdds, required this.balance, required this.available, required this.units,
  });

  /// Same rules as the web version: ROI is profit over settled, non-void
  /// stakes; win rate counts won, lost and cashed-out bets.
  factory Stats.compute(Settings s, List<Bet> bets, List<BankTx> txs) {
    final settled = bets.where((b) => b.isSettled).toList();
    final profit = settled.fold<double>(0, (a, b) => a + b.profit);
    final turnover = settled
        .where((b) => b.status != BetStatus.voided)
        .fold<double>(0, (a, b) => a + b.stake);
    final dep = txs.where((t) => t.kind == TxKind.deposit).fold<double>(0, (a, t) => a + t.amount);
    final wd = txs.where((t) => t.kind == TxKind.withdrawal).fold<double>(0, (a, t) => a + t.amount);
    final pending = bets.where((b) => b.status == BetStatus.pending).toList();
    final exposure = pending.fold<double>(0, (a, b) => a + b.stake);
    // Cash outs count too: a win when they locked in a profit, else a loss.
    final wins = bets.where((b) => b.countsAsWin == true).length;
    final losses = bets.where((b) => b.countsAsWin == false).length;
    final graded = bets.where((b) => b.isGraded).toList();
    final avgOdds = graded.isEmpty ? 0.0 : graded.fold<double>(0, (a, b) => a + b.odds) / graded.length;
    final balance = s.startBankroll + dep - wd + profit;
    return Stats(
      profit: profit,
      turnover: turnover,
      roi: turnover == 0 ? 0 : profit / turnover,
      deposits: dep,
      withdrawals: wd,
      exposure: exposure,
      pendingCount: pending.length,
      wins: wins,
      losses: losses,
      count: bets.length,
      settledCount: settled.length,
      winRate: (wins + losses) == 0 ? 0 : wins / (wins + losses),
      avgOdds: avgOdds,
      balance: balance,
      available: balance - exposure,
      units: s.unit == 0 ? 0 : profit / s.unit,
    );
  }
}

class DatePoint {
  final DateTime date;
  final double value;
  const DatePoint(this.date, this.value);
}

/// Bankroll after each day's settled bets, deposits and withdrawals.
List<DatePoint> bankrollSeries(Settings s, List<Bet> bets, List<BankTx> txs) {
  final events = <(String, double)>[
    for (final b in bets.where((b) => b.isSettled)) (b.date, b.profit),
    for (final t in txs) (t.date, t.signed),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final start = [s.startDate, if (events.isNotEmpty) events.first.$1]..sort();
  final pts = <(String, double)>[(start.first, s.startBankroll)];
  var v = s.startBankroll;
  for (final e in events) {
    v += e.$2;
    if (pts.last.$1 == e.$1) {
      pts[pts.length - 1] = (e.$1, v);
    } else {
      pts.add((e.$1, v));
    }
  }
  return [for (final p in pts) DatePoint(DateTime.parse(p.$1), p.$2)];
}

/// Settled profit grouped by month (yyyy-MM), oldest first, last 12 months.
List<(String, double)> profitByMonth(List<Bet> bets) {
  final m = <String, double>{};
  for (final b in bets.where((b) => b.isSettled)) {
    final k = b.date.substring(0, 7);
    m[k] = (m[k] ?? 0) + b.profit;
  }
  final keys = m.keys.toList()..sort();
  return [for (final k in keys.skip(keys.length > 12 ? keys.length - 12 : 0)) (k, m[k]!)];
}

class GroupStat {
  final String label;
  final double profit;
  final int count;
  final double turnover;

  /// Bets that count in the win rate, and the sum of their odds.
  final int wins, losses;
  final double gradedOdds;
  const GroupStat(this.label, this.profit, this.count, this.turnover, {this.wins = 0, this.losses = 0, this.gradedOdds = 0});
  double get roi => turnover == 0 ? 0 : profit / turnover;
  double get winRate => wins + losses == 0 ? 0 : wins / (wins + losses);
  double get avgOdds => wins + losses == 0 ? 0 : gradedOdds / (wins + losses);

  /// The win rate the average odds need to break even (1 / odds).
  double get breakEven => avgOdds <= 1 ? 0 : 1 / avgOdds;
}

/// Settled bets grouped by [key], best profit first unless [order] gives
/// the order of the keys (keys not in it go last).
List<GroupStat> profitBy(List<Bet> bets, String Function(Bet) key, {List<String>? order}) {
  final m = <String, (double, int, double, int, int, double)>{};
  for (final b in bets.where((b) => b.isSettled)) {
    final k = key(b);
    final c = m[k] ?? (0.0, 0, 0.0, 0, 0, 0.0);
    final w = b.countsAsWin;
    m[k] = (
      c.$1 + b.profit,
      c.$2 + 1,
      c.$3 + (b.status == BetStatus.voided ? 0 : b.stake),
      c.$4 + (w == true ? 1 : 0),
      c.$5 + (w == false ? 1 : 0),
      c.$6 + (w == null ? 0 : b.odds),
    );
  }
  final out = [
    for (final e in m.entries)
      GroupStat(e.key, e.value.$1, e.value.$2, e.value.$3, wins: e.value.$4, losses: e.value.$5, gradedOdds: e.value.$6),
  ];
  if (order == null) return out..sort((a, b) => b.profit.compareTo(a.profit));
  int rank(String k) => order.contains(k) ? order.indexOf(k) : order.length;
  return out..sort((a, b) => rank(a.label).compareTo(rank(b.label)));
}

/// Settled profit by sport, best first.
List<GroupStat> profitBySport(List<Bet> bets) => profitBy(bets, (b) => b.sport);

/// Odds bands for the odds chart, shortest first.
const oddsBands = ['< 1.50', '1.50 – 1.99', '2.00 – 2.99', '3.00 – 4.99', '5.00 +'];

String oddsBand(double odds) => odds < 1.5
    ? oddsBands[0]
    : odds < 2
        ? oddsBands[1]
        : odds < 3
            ? oddsBands[2]
            : odds < 5
                ? oddsBands[3]
                : oddsBands[4];

/// The time windows the Charts tab can show.
enum ChartPeriod { days30, days90, year, all }

/// The first day [p] covers, counted back from [today]; null for all time.
String? periodStart(ChartPeriod p, DateTime today) => switch (p) {
      ChartPeriod.days30 => isoDate(today.subtract(const Duration(days: 29))),
      ChartPeriod.days90 => isoDate(today.subtract(const Duration(days: 89))),
      ChartPeriod.year => isoDate(DateTime(today.year)),
      ChartPeriod.all => null,
    };

/// [points] from [from] on, starting with the balance carried into that day.
List<DatePoint> seriesFrom(List<DatePoint> points, String? from) {
  if (from == null || points.isEmpty) return points;
  final d = DateTime.parse(from);
  final before = points.where((p) => p.date.isBefore(d)).toList();
  final after = points.where((p) => !p.date.isBefore(d)).toList();
  if (before.isEmpty) return after;
  return [if (after.isEmpty || after.first.date != d) DatePoint(d, before.last.value), ...after];
}

/// One settled bet on the per-bet charts.
class BetPoint {
  final Bet bet;
  final double profit;

  /// Profit of every settled bet up to and including this one.
  final double cumulative;
  const BetPoint(this.bet, this.profit, this.cumulative);
}

/// Settled bets in the order they were played, with running profit.
List<BetPoint> profitPerBet(List<Bet> bets) {
  final settled = bets.where((b) => b.isSettled).toList()
    ..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.created.compareTo(b.created);
    });
  var run = 0.0;
  return [
    for (final b in settled) BetPoint(b, b.profit, run += b.profit),
  ];
}

/// Largest fall of the running profit from a high point, as a positive
/// amount, and the index of the bet where it bottomed out (-1 if none).
(double, int) maxDrawdown(List<BetPoint> points) {
  var peak = 0.0, worst = 0.0, at = -1;
  for (var i = 0; i < points.length; i++) {
    final v = points[i].cumulative;
    if (v > peak) peak = v;
    if (peak - v > worst) {
      worst = peak - v;
      at = i;
    }
  }
  return (worst, at);
}

class Streaks {
  /// Positive for wins in a row, negative for losses, 0 with none.
  final int current;
  final int bestWin, worstLoss;
  const Streaks(this.current, this.bestWin, this.worstLoss);
}

/// Win and loss runs over the bets in [points] that count in the win rate.
Streaks streaks(List<BetPoint> points) {
  var cur = 0, best = 0, worst = 0;
  for (final p in points) {
    final w = p.bet.countsAsWin;
    if (w == null) continue;
    cur = w ? (cur > 0 ? cur + 1 : 1) : (cur < 0 ? cur - 1 : -1);
    if (cur > best) best = cur;
    if (-cur > worst) worst = -cur;
  }
  return Streaks(cur, best, worst);
}

/// Odds parsing and display in decimal or American format.
double? parseOdds(String input, OddsFormat fmt) {
  final n = double.tryParse(input.trim().replaceAll('−', '-').replaceAll(',', '.').replaceAll('+', ''));
  if (n == null || !n.isFinite) return null;
  if (fmt == OddsFormat.american) {
    if (n.abs() < 100) return null;
    return n > 0 ? 1 + n / 100 : 1 + 100 / n.abs();
  }
  return n > 1 ? n : null;
}

String formatOdds(double dec, OddsFormat fmt) {
  if (dec <= 1) return '–';
  if (fmt == OddsFormat.american) {
    return dec >= 2 ? '+${((dec - 1) * 100).round()}' : '-${(100 / (dec - 1)).round()}';
  }
  return dec.toStringAsFixed(2);
}

/// Number of bets per type, for the summary.
Map<BetType, int> countByType(List<Bet> bets) {
  final m = <BetType, int>{};
  for (final b in bets) {
    m[b.type] = (m[b.type] ?? 0) + 1;
  }
  return m;
}
