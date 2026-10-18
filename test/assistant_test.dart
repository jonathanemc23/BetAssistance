import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/logic/assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final details = parseMatchDetails(File('test/data/espn_summary_pre.json').readAsStringSync());
  final match = Match(
    id: '401878771',
    league: const League('eng.1', 'Premier League'),
    kickoff: DateTime.utc(2026, 10, 18, 19),
    home: const Team('Everton', 'Everton', null, null),
    away: const Team('Chelsea', 'Chelsea', null, null),
    state: MatchState.scheduled,
    detail: '',
  );
  const a = DataAssistant();

  test('every suggested question has a topic, in English and Spanish', () {
    expect(suggestedQuestions.map(DataAssistant.topicOf),
        ['summary', 'form', 'h2h', 'goals', 'table', 'odds', 'lineups', 'news']);
    expect(DataAssistant.topicOf('¿Cuál es la cuota del empate?'), 'odds');
    expect(DataAssistant.topicOf('historial entre ellos'), 'h2h');
    expect(DataAssistant.topicOf('¿Quién gana?'), 'summary');
    expect(DataAssistant.topicOf('ambos marcan?'), 'goals');
    expect(DataAssistant.topicOf('what formation will they use'), 'lineups');
    expect(DataAssistant.topicOf('hello'), isNull);
  });

  test('answers come from the match data and are saved as notes', () async {
    for (final q in suggestedQuestions) {
      final r = await a.ask(q, match, details);
      expect(r.note, isNotNull, reason: q);
      expect(r.text, isNotEmpty);
    }
    final odds = await a.ask('Best odds and implied chances', match, details);
    expect(odds.text, contains('Everton: 3.15')); // best of DraftKings 3.15 and Bet 365 3.00
    expect(odds.text, contains('Bookmaker margin'));
    final summary = await a.ask('Who is the favourite?', match, details);
    expect(summary.text, contains('Market favourite: Chelsea'));
    final form = await a.ask('How is Everton doing?', match, details);
    expect(form.note!.title, 'Everton form');
    expect(form.text, isNot(contains('Chelsea')));
    final unknown = await a.ask('hello', match, details);
    expect(unknown.note, isNull);
  });
}
