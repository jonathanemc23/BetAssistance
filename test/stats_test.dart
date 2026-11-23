import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/stats.dart';
import 'package:flutter_test/flutter_test.dart';

Bet bet(BetStatus s, {double stake = 10, double odds = 2, String date = '2026-01-10', String sport = 'Soccer', double? cashout}) =>
    Bet(selection: 'x', date: date, stake: stake, odds: odds, status: s, sport: sport, cashout: cashout, created: '');

void main() {
  const settings = Settings(startBankroll: 1000, startDate: '2026-01-01', unit: 10);

  test('profit per status', () {
    expect(bet(BetStatus.won, odds: 2.5).profit, 15);
    expect(bet(BetStatus.lost).profit, -10);
    expect(bet(BetStatus.cashout, cashout: 14).profit, 4);
    expect(bet(BetStatus.push).profit, 0);
    expect(bet(BetStatus.voided).profit, 0);
    expect(bet(BetStatus.pending).profit, 0);
  });

  test('bankroll, ROI, win rate and exposure', () {
    final bets = [
      bet(BetStatus.won, odds: 2.0), // +10
      bet(BetStatus.lost), // -10
      bet(BetStatus.won, odds: 3.0), // +20
      bet(BetStatus.voided, stake: 50), // not in turnover
      bet(BetStatus.pending, stake: 25),
    ];
    final txs = [
      const BankTx(kind: TxKind.deposit, amount: 200, date: '2026-01-05'),
      const BankTx(kind: TxKind.withdrawal, amount: 50, date: '2026-01-20'),
    ];
    final s = Stats.compute(settings, bets, txs);
    expect(s.profit, 20);
    expect(s.turnover, 30);
    expect(s.roi, closeTo(20 / 30, 1e-9));
    expect(s.winRate, closeTo(2 / 3, 1e-9));
    expect(s.count, 5);
    expect(s.pendingCount, 1);
    expect(s.exposure, 25);
    expect(s.balance, 1000 + 200 - 50 + 20);
    expect(s.available, s.balance - 25);
    expect(s.units, 2);
  });

  test('a cash out counts as a win only when it clearly beats the stake', () {
    final bets = [
      bet(BetStatus.cashout, cashout: 15), // well above the stake: win
      bet(BetStatus.cashout, cashout: 10.2), // about the stake back: loss
      bet(BetStatus.cashout, cashout: 6), // below the stake: loss
      bet(BetStatus.won),
    ];
    expect(bets.map((b) => b.countsAsWin), [true, false, false, true]);
    final s = Stats.compute(settings, bets, []);
    expect(s.winRate, closeTo(2 / 4, 1e-9));
    expect(s.profit, closeTo(5 + 0.2 - 4 + 10, 1e-9));
  });

  test('empty ledger has no division by zero', () {
    final s = Stats.compute(settings, [], []);
    expect(s.roi, 0);
    expect(s.winRate, 0);
    expect(s.balance, 1000);
  });

  test('bankroll series merges same-day events in date order', () {
    final pts = bankrollSeries(settings, [
      bet(BetStatus.won, date: '2026-01-10'),
      bet(BetStatus.lost, date: '2026-01-10'),
      bet(BetStatus.won, date: '2026-01-03', odds: 1.5),
      bet(BetStatus.pending, date: '2026-01-12'),
    ], [const BankTx(kind: TxKind.deposit, amount: 100, date: '2026-01-05')]);
    expect([for (final p in pts) p.value], [1000, 1005, 1105, 1105]);
    expect(pts.first.date, DateTime(2026, 1, 1));
  });

  test('profit by month and sport', () {
    final bets = [
      bet(BetStatus.won, date: '2026-01-10'),
      bet(BetStatus.lost, date: '2026-02-01', sport: 'Tennis'),
      bet(BetStatus.won, date: '2026-02-03', sport: 'Tennis', odds: 3),
    ];
    expect(profitByMonth(bets), [('2026-01', 10.0), ('2026-02', 10.0)]);
    final bySport = profitBySport(bets);
    expect(bySport.map((g) => g.label), ['Soccer', 'Tennis']);
    expect(bySport.last.count, 2);
    expect(bySport.last.roi, 0.5);
  });

  test('odds parsing and formatting', () {
    expect(parseOdds('2.50', OddsFormat.decimal), 2.5);
    expect(parseOdds('2,50', OddsFormat.decimal), 2.5);
    expect(parseOdds('1', OddsFormat.decimal), isNull);
    expect(parseOdds('+150', OddsFormat.american), 2.5);
    expect(parseOdds('-200', OddsFormat.american), 1.5);
    expect(parseOdds('50', OddsFormat.american), isNull);
    expect(formatOdds(2.5, OddsFormat.american), '+150');
    expect(formatOdds(1.5, OddsFormat.american), '-200');
    expect(formatOdds(1.91, OddsFormat.decimal), '1.91');
  });

  test('profit per bet, running total, drawdown and streaks', () {
    final bets = [
      bet(BetStatus.won, date: '2026-01-01'), // +10 -> 10
      bet(BetStatus.lost, date: '2026-01-02'), // -10 -> 0
      bet(BetStatus.lost, date: '2026-01-03'), // -10 -> -10
      bet(BetStatus.pending, date: '2026-01-03'),
      bet(BetStatus.push, date: '2026-01-04'), // 0 -> -10, not a streak break
      bet(BetStatus.lost, date: '2026-01-05'), // -10 -> -20
      bet(BetStatus.won, odds: 4, date: '2026-01-06'), // +30 -> 10
    ];
    final pts = profitPerBet(bets);
    expect(pts.map((p) => p.cumulative), [10, 0, -10, -10, -20, 10]);
    final (dd, at) = maxDrawdown(pts);
    expect(dd, 30);
    expect(at, 4);
    final s = streaks(pts);
    expect(s.current, 1);
    expect(s.bestWin, 1);
    expect(s.worstLoss, 3);
    expect(maxDrawdown(const []), (0.0, -1));
  });

  test('groups by odds band keep their order and know the break-even rate', () {
    final bets = [
      bet(BetStatus.won, odds: 1.4),
      bet(BetStatus.lost, odds: 1.4),
      bet(BetStatus.won, odds: 2.5),
      bet(BetStatus.lost, odds: 2.5),
      bet(BetStatus.lost, odds: 2.5),
    ];
    final g = profitBy(bets, (b) => oddsBand(b.odds), order: oddsBands);
    expect(g.map((x) => x.label), ['< 1.50', '2.00 – 2.99']);
    expect(g[0].winRate, 0.5);
    expect(g[0].breakEven, closeTo(1 / 1.4, 1e-9));
    expect(g[1].profit, 15 - 20);
    expect(g[1].winRate, closeTo(1 / 3, 1e-9));
    expect(oddsBand(5), '5.00 +');
  });

  test('a period starts on the right day and carries the balance in', () {
    final today = DateTime(2026, 3, 30);
    expect(periodStart(ChartPeriod.days30, today), '2026-03-01');
    expect(periodStart(ChartPeriod.year, today), '2026-01-01');
    expect(periodStart(ChartPeriod.all, today), isNull);
    final pts = [DatePoint(DateTime(2026, 1, 1), 100), DatePoint(DateTime(2026, 2, 1), 150), DatePoint(DateTime(2026, 3, 10), 120)];
    final cut = seriesFrom(pts, '2026-03-01');
    expect(cut.map((p) => p.value), [150, 120]);
    expect(cut.first.date, DateTime(2026, 3, 1));
  });
}

