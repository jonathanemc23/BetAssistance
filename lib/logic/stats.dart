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
  const GroupStat(this.label, this.profit, this.count, this.turnover);
  double get roi => turnover == 0 ? 0 : profit / turnover;
}

/// Settled profit by sport, best first.
List<GroupStat> profitBySport(List<Bet> bets) {
  final m = <String, (double, int, double)>{};
  for (final b in bets.where((b) => b.isSettled)) {
    final cur = m[b.sport] ?? (0.0, 0, 0.0);
    m[b.sport] = (cur.$1 + b.profit, cur.$2 + 1, cur.$3 + (b.status == BetStatus.voided ? 0 : b.stake));
  }
  return [for (final e in m.entries) GroupStat(e.key, e.value.$1, e.value.$2, e.value.$3)]
    ..sort((a, b) => b.profit.compareTo(a.profit));
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
