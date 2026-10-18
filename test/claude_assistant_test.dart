import 'dart:convert';
import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/logic/claude_assistant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  test('sends the match as context, keeps the chat and lists web sources', () async {
    final sent = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      expect(req.headers['x-api-key'], 'sk-test');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      sent.add(body);
      // First round pauses mid search; the second finishes the answer.
      if (sent.length == 1) {
        return json({
          'stop_reason': 'pause_turn',
          'content': [
            {'type': 'text', 'text': 'Pickford está en duda. '},
          ],
        });
      }
      return json({
        'stop_reason': 'end_turn',
        'content': [
          {
            'type': 'server_tool_use',
            'id': 's1',
            'name': 'web_search',
            'input': {'query': 'Everton injuries'},
          },
          {
            'type': 'text',
            'text': 'Se espera que juegue.',
            'citations': [
              {'type': 'web_search_result_location', 'url': 'https://example.com/a', 'title': 'Everton news'},
            ],
          },
        ],
      });
    });
    final a = ClaudeAssistant('sk-test', client: client, now: () => DateTime.utc(2026, 10, 18));
    final r = await a.ask(
      '¿Juega Pickford?',
      match,
      details,
      history: [
        (false, 'Hi, ask me anything.'), // a leading assistant turn is dropped
        (true, 'Who is the favourite?'),
        (false, 'Chelsea.'),
      ],
    );
    expect(sent, hasLength(2));
    final first = sent.first;
    expect(first['model'], 'claude-opus-5-5');
    expect(first['fallbacks'], 'default');
    expect(first['system'], contains('Everton vs Chelsea (Premier League)'));
    expect(first['system'], contains('Today: 2026-10-18'));
    expect((first['messages'] as List).map((m) => m['role']), ['user', 'assistant', 'user']);
    expect((sent.last['messages'] as List).last['role'], 'assistant'); // the paused turn is sent back
    expect(r.text, startsWith('Pickford está en duda. Se espera que juegue.'));
    expect(r.text, contains('• Everton news (https://example.com/a)'));
    expect(r.note!.category, 'Research');
  });

  test('explains key, limit, refusal and connection problems', () async {
    Future<String> reply(http.Response res) =>
        ClaudeAssistant('k', client: MockClient((_) async => res)).ask('q', match, details).then((r) => r.text);
    expect(
      await reply(
        json({
          'error': {'message': 'invalid x-api-key'},
        }, 401),
      ),
      contains('key in Settings'),
    );
    expect(
      await reply(
        json({
          'error': {'message': 'rate'},
        }, 429),
      ),
      contains('limit'),
    );
    expect(
      await reply(
        json({
          'error': {'message': 'Your credit balance is too low'},
        }, 400),
      ),
      contains('no credit'),
    );
    expect(await reply(json({'stop_reason': 'refusal', 'content': []})), contains("can't help"));
    final down = ClaudeAssistant('k', client: MockClient((_) async => throw const SocketException('down')));
    final r = await down.ask('q', match, details);
    expect(r.text, contains("couldn't reach"));
    expect(r.note, isNull);
  });
}
