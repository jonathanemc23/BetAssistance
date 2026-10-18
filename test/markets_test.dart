import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/bet_review.dart';
import 'package:bank_track/logic/markets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every market builds a selection that reads back as the same market', () {
    final picks = <String, String>{};
    for (final m in markets) {
      final sides = m.sides('Arsenal', 'Chelsea');
      final text = m.hasText
          ? (m.id == 'correct_score'
                ? '2-1'
                : m.id == 'scorer'
                ? 'Saka'
                : 'Arsenal win both halves')
          : '';
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
}
