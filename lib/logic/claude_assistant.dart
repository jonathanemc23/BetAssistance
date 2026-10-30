import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../data/fixtures.dart';
import '../l10n/l10n.dart';
import 'assistant.dart';

/// Preference that holds the user's Anthropic API key.
const aiKeyPref = 'ai.key';

/// Matchboard chat backed by Claude with web search, using the user's own
/// Anthropic API key (Settings › AI chat). It answers any question about the
/// match, with the app's match data as context and the web for the rest.
/// Without a key the app keeps using [DataAssistant].
class ClaudeAssistant implements MatchAssistant {
  ClaudeAssistant(this.apiKey, {http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final String apiKey;
  final http.Client _client;
  final DateTime Function() _now;

  static const model = 'claude-opus-5-5';
  static const _url = 'https://api.anthropic.com/v1/messages';

  @override
  String get name => 'Claude with web search';

  @override
  Future<AssistantReply> ask(
    String question,
    Match match,
    MatchDetails details, {
    List<(bool, String)> history = const [],
  }) async {
    final messages = <Map<String, Object?>>[
      // The last few turns, so follow-up questions make sense.
      for (final (user, text) in history.length > 8 ? history.sublist(history.length - 8) : history)
        {'role': user ? 'user' : 'assistant', 'content': text},
      {'role': 'user', 'content': question},
    ];
    // Conversations must start with the user and alternate.
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }

    final content = <Map<String, Object?>>[];
    try {
      // Web search can pause a long turn; send it back to let it finish.
      for (var round = 0; round < 3; round++) {
        final res = await _client
            .post(
              Uri.parse(_url),
              headers: {
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
                'anthropic-beta': 'server-side-fallback-2026-07-01',
                'content-type': 'application/json',
                // The web version calls the API from the browser with the user's own key.
                if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
              },
              body: jsonEncode({
                'model': model,
                'max_tokens': 16000,
                'output_config': {'effort': 'low'},
                'fallbacks': 'default',
                'system': _system(match, details),
                'tools': [
                  {'type': 'web_search_20260209', 'name': 'web_search', 'max_uses': 5},
                ],
                'messages': [
                  ...messages,
                  if (content.isNotEmpty) {'role': 'assistant', 'content': content},
                ],
              }),
            )
            .timeout(const Duration(minutes: 3));
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (res.statusCode != 200) return AssistantReply(_error(res.statusCode, body));
        if (body['stop_reason'] == 'refusal') {
          return AssistantReply(tr("I can't help with that question. Try asking it another way."));
        }
        content.addAll((body['content'] as List).cast<Map<String, Object?>>());
        if (body['stop_reason'] != 'pause_turn') break;
      }
    } catch (_) {
      return AssistantReply(tr("I couldn't reach the AI right now. Check your connection and try again."));
    }

    final text = StringBuffer();
    final sources = <String, String>{};
    for (final b in content) {
      if (b['type'] != 'text') continue;
      text.write(b['text']);
      for (final c in (b['citations'] as List? ?? const [])) {
        final url = (c as Map)['url'] as String?;
        if (url != null) sources[url] = (c['title'] as String?) ?? url;
      }
    }
    var answer = text.toString().trim();
    if (answer.isEmpty) return AssistantReply(tr("I couldn't find an answer to that. Try asking another way."));
    if (sources.isNotEmpty) {
      answer += '\n\n${tr('Sources:')}\n${sources.entries.take(4).map((e) => '• ${e.value} (${e.key})').join('\n')}';
    }
    final title = question.length > 48 ? '${question.substring(0, 45)}…' : question;
    return AssistantReply(answer, note: NoteDraft('Research', title, answer));
  }

  static String _error(int status, Object? body) {
    final message = body is Map && body['error'] is Map ? (body['error'] as Map)['message'] : null;
    return switch (status) {
      401 || 403 => tr('The AI key in Settings was not accepted. Check it and try again.'),
      429 => tr('The AI is busy or your Anthropic account hit its limit. Try again in a minute.'),
      400 when '$message'.contains('credit') => tr('Your Anthropic account has no credit left. Add credit and try again.'),
      _ => tr("The AI couldn't answer right now (error {status}). Try again.", {'status': status}),
    };
  }

  /// What the app knows about the match, given to Claude as background.
  String _system(Match m, MatchDetails d) {
    final b = DataAssistant.bestOdds(m, d);
    final lines = <String>[
      'You are the research assistant in BetPilot, a betting tracker app. The user is studying one football '
          'match and may ask anything: teams, players, injuries, tactics, referees, weather, odds, betting markets or '
          'general questions. Answer in the language the user writes in. Be concise and concrete: a short answer '
          'first, then the key facts. Use web search for anything recent or not in the data below. Never promise '
          'a result; when asked for a pick, give the reasoning and the risk.',
      if (L10n.spanish) 'The app is set to Spanish: answer in Spanish unless the user writes in another language.',
      '',
      'Today: ${_now().toIso8601String().substring(0, 10)}',
      'Match: ${m.home.name} vs ${m.away.name} (${m.league.name}), kick-off ${m.kickoff.toUtc().toIso8601String()} UTC.',
      if (d.state == MatchState.live || d.state == MatchState.finished)
        'Status: ${d.clock}, score ${d.homeScore ?? '-'}-${d.awayScore ?? '-'}.',
      if (b != null)
        'Best 1X2 odds: ${m.home.name} ${b.home?.toStringAsFixed(2) ?? '-'}, draw ${b.draw?.toStringAsFixed(2) ?? '-'}, '
            '${m.away.name} ${b.away?.toStringAsFixed(2) ?? '-'}.',
      if (d.home.form.isNotEmpty) '${m.home.name} recent form (newest first): ${d.home.form}.',
      if (d.away.form.isNotEmpty) '${m.away.name} recent form (newest first): ${d.away.form}.',
      if (d.h2hSummary.isNotEmpty) 'Head to head: ${d.h2hSummary}.',
      for (final n in d.news.take(3)) 'News: ${n.headline}',
    ];
    return lines.join('\n');
  }
}
