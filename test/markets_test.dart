import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/bet_review.dart';
import 'package:bank_track/logic/markets.dart';
import 'package:bank_track/ui/market_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every market builds a selection that reads back as the same market', () {
    final picks = <String, String>{};
    for (final m in markets) {
      final sides = m.sides('Arsenal', 'Chelsea');
      final text = m.hasText ? (m.id == 'correct_score' ? '2-1' : m.id == 'scorer' ? 'Saka' : 'Arsenal win both halves') : '';
      final sel = m.selection(side: sides.isEmpty ? null : sides.last, line: m.line, text: text);
      picks[m.id] = sel;
      if (m.id != 'other') expect(marketOf(sel), m.id, reason: sel);
    }
    expect(picks['handicap'], 'Chelsea -0.5');
    expect(picks['goals'], 'Under 2.5 goals');
    expect(picks['corners'], 'Under 9.5 corners');
    expect(picks['cards'], 'Under 4.5 cards');
    expect(picks['btts'], 'Both teams to score: No');
    expect(picks['correct_score'], 'Correct score 2-1');
    expect(picks['scorer'], 'Saka to score');
    expect(marketById('handicap').selection(side: 'Arsenal', line: 1.25), 'Arsenal +1.25');
  });

  test('older free-text picks are given a market', () {
    expect(marketOf('Arsenal to win'), 'result');
    expect(marketOf('Draw'), 'result');
    expect(marketOf('Over 2.5 goals'), 'goals');
    expect(marketOf('Liverpool -1.5'), 'handicap');
    expect(marketOf('Arsenal +0.5'), 'handicap');
    expect(marketOf('Both teams to score'), 'btts');
    expect(marketOf('Over 10.5 corners'), 'corners');
    expect(marketOf('Underdog by KO'), 'other');
    expect(teamsOf('Arsenal vs Chelsea'), ('Arsenal', 'Chelsea'));
    expect(teamsOf('UFC main event'), ('Home', 'Away'));
  });

  test('picks are graded from the score where the market allows it', () {
    BetStatus? g(String market, String sel, int h, int a) => gradePick(market, sel, 'Arsenal', 'Chelsea', h, a);
    expect(g('result', 'Arsenal to win', 2, 1), BetStatus.won);
    expect(g('result', 'Draw', 2, 1), BetStatus.lost);
    expect(g('double_chance', 'Chelsea or draw', 1, 1), BetStatus.won);
    expect(g('dnb', 'Chelsea draw no bet', 1, 1), BetStatus.push);
    expect(g('handicap', 'Arsenal -1.5', 2, 1), BetStatus.lost);
    expect(g('handicap', 'Arsenal -1', 2, 1), BetStatus.push);
    expect(g('handicap', 'Chelsea +1.5', 2, 1), BetStatus.won);
    expect(g('handicap', 'Arsenal -0.75', 2, 1), isNull); // quarter line
    expect(g('goals', 'Over 2.5 goals', 2, 1), BetStatus.won);
    expect(g('goals', 'Under 3 goals', 2, 1), BetStatus.push);
    expect(g('btts', 'Both teams to score: Yes', 2, 0), BetStatus.lost);
    expect(g('correct_score', 'Correct score 2-1', 2, 1), BetStatus.won);
    expect(g('corners', 'Over 9.5 corners', 2, 1), isNull);
  });

  test('team totals, win to nil and quarter lines settle from the score', () {
    BetStatus? g(String sel, int h, int a) => gradePick(marketOf(sel), sel, 'Arsenal', 'Chelsea', h, a);
    expect(marketOf('Arsenal over 1.5 goals'), 'team_goals');
    expect(marketOf('Chelsea to win to nil'), 'win_to_nil');
    expect(g('Arsenal over 1.5 goals', 2, 3), BetStatus.won);
    expect(g('Chelsea under 1.5 goals', 2, 3), BetStatus.lost);
    expect(g('Arsenal over 2 goals', 2, 3), BetStatus.push);
    expect(g('Arsenal to win to nil', 2, 0), BetStatus.won);
    expect(g('Arsenal to win to nil', 2, 1), BetStatus.lost);
    expect(g('Arsenal -0.25', 1, 0), BetStatus.won); // both halves win
    expect(g('Arsenal -0.25', 0, 0), isNull); // half push, half lost
    expect(g('Chelsea +0.75', 1, 0), isNull);
    expect(g('Chelsea +0.75', 0, 2), BetStatus.won);
    expect(g('Over 2.25 goals', 3, 1), BetStatus.won);
    expect(g('Under 2.75 goals', 1, 0), BetStatus.won);
    expect(g('Over 220.5 points', 110, 111), BetStatus.won);
  });

  test('markets follow the sport', () {
    expect(marketsFor('soccer').first.id, 'result');
    expect(marketsFor('soccer').map((m) => m.id), containsAll(['double_chance', 'handicap', 'btts', 'team_goals']));
    final nba = marketsFor('basketball');
    expect(nba.map((m) => m.id), isNot(contains('double_chance')));
    expect(nba.first.sides('Lakers', 'Celtics', draws: false), ['Lakers', 'Celtics']);
    final total = nba.firstWhere((m) => m.id == 'goals');
    expect(total.selection(side: 'Over', line: total.line, unit: 'points'), 'Over 220.5 points');
  });

  test('bookmaker prices are found by the selection the sheet builds', () {
    const o = MatchOdds(home: 2.1, draw: 3.4, away: 3.2, provider: 'Book', totalLine: 2.5, over: 1.9, under: 1.95,
        extras: [('Double chance 1X', 1.3)]);
    expect(bestPrice('Arsenal to win', [o], 'Arsenal', 'Chelsea'), (2.1, 'Book'));
    expect(bestPrice('Arsenal or draw', [o], 'Arsenal', 'Chelsea')!.$1, 1.3);
    expect(bestPrice('Under 2.5 goals', [o], 'Arsenal', 'Chelsea')!.$1, 1.95);
    expect(bestPrice('Arsenal -0.5', [o], 'Arsenal', 'Chelsea'), isNull);
  });
}
