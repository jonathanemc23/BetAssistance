import 'package:bank_track/logic/slip_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// OCR lines laid out like a phone screenshot: each inner list is one row,
/// its first piece on the left and the second (the price) on the right.
List<SlipLine> screen(List<List<String>> rows) => [
      for (final (i, r) in rows.indexed)
        for (final (j, t) in r.indexed)
          SlipLine(t, left: j == 0 ? 24 : 600, right: j == 0 ? 400 : 680, top: i * 48.0 + (j * 3), bottom: i * 48.0 + 30 + (j * 3)),
    ];

void main() {
  test('reads an English slip with the pick and price first', () {
    final r = parseSlip(screen([
      ['Bet Slip'],
      ['Arsenal', '1.85'],
      ['Full Time Result'],
      ['Arsenal v Chelsea'],
      ['Over 2.5', '1.90'],
      ['Goals Over/Under'],
      ['Liverpool v Everton'],
      ['Both Teams to Score - Yes', '2.10'],
      ['Real Madrid v Getafe'],
      ['Stake', '£10.00'],
      ['To Return', '£73.82'],
    ]));
    expect(r.legs.map((l) => (l.selection, l.event, l.market, l.odds)), [
      ('Arsenal', 'Arsenal v Chelsea', 'result', 1.85),
      ('Over 2.5', 'Liverpool v Everton', 'goals', 1.90),
      ('Both Teams to Score - Yes', 'Real Madrid v Getafe', 'btts', 2.10),
    ]);
    expect(r.stake, 10);
  });

  test('reads a Spanish slip with the match first, comma prices and pesos', () {
    final r = parseSlip(screen([
      ['Apuesta combinada (3)'],
      ['Millonarios - Santa Fe'],
      ['1X2 Tiempo reglamentario'],
      ['Millonarios', '2,05'],
      ['Hoy 18:00'],
      ['Junior - Nacional'],
      ['Total de goles'],
      ['Más de 2.5', '1,80'],
      ['América - Cali'],
      ['Ambos equipos marcan'],
      ['Sí', '1,95'],
      ['Cuota total', '7,19'],
      ['Apuesta', '\$ 10.000'],
      ['Ganancia potencial', '\$ 71.900'],
    ]));
    expect(r.legs.map((l) => (l.selection, l.event, l.market, l.odds)), [
      ('Millonarios', 'Millonarios - Santa Fe', 'result', 2.05),
      ('Más de 2.5', 'Junior - Nacional', 'goals', 1.80),
      ('Sí', 'América - Cali', 'btts', 1.95),
    ]);
    expect(r.stake, 10000);
    expect(r.totalOdds, 7.19);
  });

  test('reads prices in the same line, American odds and handicaps', () {
    final r = parseSlip(screen([
      ['Parlay'],
      ['Chelsea @ Arsenal'],
      ['Moneyline'],
      ['Chelsea +150'],
      ['Inter vs Milan'],
      ['Handicap'],
      ['Inter -1.5 @ 2.40'],
      ['Wager: \$20.00'],
    ]));
    expect(r.legs.map((l) => (l.selection, l.event, l.market)), [
      ('Chelsea', 'Chelsea @ Arsenal', 'result'),
      ('Inter -1.5', 'Inter vs Milan', 'handicap'),
    ]);
    expect(r.legs[0].odds, 2.5);
    expect(r.legs[1].odds, 2.4);
    expect(r.stake, 20);
  });

  test('a picture with no prices gives nothing', () {
    expect(parseSlip(screen([['Hello'], ['Liverpool v Everton']])).legs, isEmpty);
    expect(parseSlip(const []).legs, isEmpty);
  });
}
