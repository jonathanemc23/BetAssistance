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
}
