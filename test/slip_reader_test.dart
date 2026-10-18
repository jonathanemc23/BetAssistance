import 'package:bank_track/logic/slip_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// OCR lines laid out like a phone screenshot: each inner list is one row,
/// its first piece on the left and the second (the price) on the right.
List<SlipLine> screen(List<List<String>> rows) => [
  for (final (i, r) in rows.indexed)
    for (final (j, t) in r.indexed)
      SlipLine(
        t,
        left: j == 0 ? 24 : 600,
        right: j == 0 ? 400 : 680,
        top: i * 48.0 + (j * 3),
        bottom: i * 48.0 + 30 + (j * 3),
      ),
];

void main() {
  test('reads an English slip with the pick and price first', () {
    final r = parseSlip(
      screen([
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
      ]),
    );
    expect(r.legs.map((l) => (l.selection, l.event, l.market, l.odds)), [
      ('Arsenal', 'Arsenal v Chelsea', 'result', 1.85),
      ('Over 2.5', 'Liverpool v Everton', 'goals', 1.90),
      ('Both Teams to Score - Yes', 'Real Madrid v Getafe', 'btts', 2.10),
    ]);
    expect(r.stake, 10);
  });

  test('reads a Spanish slip with the match first, comma prices and pesos', () {
    final r = parseSlip(
      screen([
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
      ]),
    );
    expect(r.legs.map((l) => (l.selection, l.event, l.market, l.odds)), [
      ('Millonarios', 'Millonarios - Santa Fe', 'result', 2.05),
      ('Más de 2.5', 'Junior - Nacional', 'goals', 1.80),
      ('Sí · Ambos equipos marcan', 'América - Cali', 'btts', 1.95),
    ]);
    expect(r.stake, 10000);
    expect(r.totalOdds, 7.19);
  });

  test('reads prices in the same line, American odds and handicaps', () {
    final r = parseSlip(
      screen([
        ['Parlay'],
        ['Chelsea @ Arsenal'],
        ['Moneyline'],
        ['Chelsea +150'],
        ['Inter vs Milan'],
        ['Handicap'],
        ['Inter -1.5 @ 2.40'],
        ['Wager: \$20.00'],
      ]),
    );
    expect(r.legs.map((l) => (l.selection, l.event, l.market)), [
      ('Chelsea', 'Chelsea @ Arsenal', 'result'),
      ('Inter -1.5', 'Inter vs Milan', 'handicap'),
    ]);
    expect(r.legs[0].odds, 2.5);
    expect(r.legs[1].odds, 2.4);
    expect(r.stake, 20);
  });

  test('a picture with no prices gives nothing', () {
    expect(
      parseSlip(
        screen([
          ['Hello'],
          ['Liverpool v Everton'],
        ]),
      ).legs,
      isEmpty,
    );
    expect(parseSlip(const []).legs, isEmpty);
  });

  test('reads a six-leg slip with the teams one under the other and kick-off dates', () {
    // Text and positions as read from a real slip screenshot.
    final r = parseSlip(const [
      SlipLine("Betano", left: 36, top: 30, right: 206, bottom: 76),
      SlipLine("Combinada de 6 \$60.000", left: 46, top: 130, right: 319, bottom: 152),
      SlipLine("23.61", left: 526, top: 129, right: 589, bottom: 154),
      SlipLine("Manchester United o Empate", left: 87, top: 209, right: 455, bottom: 238),
      SlipLine("1.55", left: 514, top: 210, right: 571, bottom: 238),
      SlipLine("Doble oportunidad", left: 94, top: 256, right: 320, bottom: 285),
      SlipLine("Leeds United", left: 98, top: 297, right: 283, bottom: 320),
      SlipLine("18/10/2026, 08:00", left: 367, top: 310, right: 582, bottom: 341),
      SlipLine("Manchester United", left: 94, top: 327, right: 355, bottom: 355),
      SlipLine("Como 1907", left: 89, top: 404, right: 235, bottom: 435),
      SlipLine("2.05", left: 513, top: 404, right: 572, bottom: 435),
      SlipLine("Ganar el partido o liderar por 2 goles", left: 94, top: 453, right: 525, bottom: 479),
      SlipLine("AC Fiorentina", left: 99, top: 493, right: 286, bottom: 516),
      SlipLine("18/10/2026, 08:00", left: 367, top: 505, right: 582, bottom: 536),
      SlipLine("Como 1907", left: 94, top: 524, right: 261, bottom: 550),
      SlipLine("Arsenal FC", left: 90, top: 601, right: 231, bottom: 629),
      SlipLine("1.62", left: 513, top: 599, right: 571, bottom: 631),
      SlipLine("Ganar el partido o liderar por 2 goles", left: 94, top: 649, right: 525, bottom: 675),
      SlipLine("Nottingham Forest", left: 100, top: 688, right: 355, bottom: 714),
      SlipLine("18/10/2026, 10:30", left: 368, top: 703, right: 582, bottom: 731),
      SlipLine("Arsenal FC", left: 94, top: 718, right: 254, bottom: 747),
      SlipLine("AC Milan", left: 89, top: 795, right: 206, bottom: 826),
      SlipLine("1.67", left: 514, top: 798, right: 570, bottom: 826),
      SlipLine("Ganar el partido o liderar por 2 goles", left: 95, top: 846, right: 525, bottom: 872),
      SlipLine("AC Milan", left: 98, top: 884, right: 232, bottom: 909),
      SlipLine("18/10/2026, 11:00", left: 368, top: 899, right: 582, bottom: 928),
      SlipLine("Atalanta", left: 98, top: 916, right: 228, bottom: 942),
      SlipLine("FC Copenhagen", left: 88, top: 991, right: 288, bottom: 1026),
      SlipLine("1.57", left: 514, top: 993, right: 572, bottom: 1024),
      SlipLine("Ganar el partido o liderar por 2 goles", left: 94, top: 1041, right: 525, bottom: 1068),
      SlipLine("FC Copenhagen", left: 111, top: 1078, right: 314, bottom: 1108),
      SlipLine("18/10/2026, 11:00", left: 368, top: 1094, right: 582, bottom: 1123),
      SlipLine("Aarhus GF", left: 96, top: 1112, right: 249, bottom: 1138),
      SlipLine("Girona FC", left: 93, top: 1189, right: 216, bottom: 1218),
      SlipLine("1.75", left: 514, top: 1190, right: 570, bottom: 1218),
      SlipLine("Ganar el partido o liderar por 2 goles", left: 94, top: 1236, right: 525, bottom: 1263),
      SlipLine("Girona FC", left: 125, top: 1274, right: 242, bottom: 1300),
      SlipLine("18/10/2026, 11:30", left: 368, top: 1292, right: 582, bottom: 1320),
      SlipLine("FC Andorra", left: 115, top: 1308, right: 260, bottom: 1334),
      SlipLine("Apuesta", left: 43, top: 1373, right: 136, bottom: 1400),
      SlipLine("\$60.000", left: 497, top: 1371, right: 590, bottom: 1399),
      SlipLine("Ganancias potenciales", left: 46, top: 1435, right: 296, bottom: 1458),
      SlipLine("\$1.417.118", left: 431, top: 1432, right: 589, bottom: 1460),
      SlipLine("CASH OUT \$140.648", left: 202, top: 1507, right: 431, bottom: 1530),
    ]);
    expect(r.legs.map((l) => (l.selection, l.event, l.odds)), [
      ('Manchester United o Empate', 'Leeds United vs Manchester United', 1.55),
      ('Como 1907 · Ganar el partido o liderar por 2 goles', 'AC Fiorentina vs Como 1907', 2.05),
      ('Arsenal FC · Ganar el partido o liderar por 2 goles', 'Nottingham Forest vs Arsenal FC', 1.62),
      ('AC Milan · Ganar el partido o liderar por 2 goles', 'AC Milan vs Atalanta', 1.67),
      ('FC Copenhagen · Ganar el partido o liderar por 2 goles', 'FC Copenhagen vs Aarhus GF', 1.57),
      ('Girona FC · Ganar el partido o liderar por 2 goles', 'Girona FC vs FC Andorra', 1.75),
    ]);
    expect(r.legs.first.market, 'double_chance');
    expect(r.legs[1].market, 'other');
    expect(r.stake, 60000);
    expect(r.totalOdds, 23.61);
  });
}
