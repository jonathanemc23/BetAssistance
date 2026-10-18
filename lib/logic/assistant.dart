import '../data/fixtures.dart';

/// One answer from the Matchboard assistant. [note] is what gets saved on the
/// board (null when the question wasn't understood).
class AssistantReply {
  const AssistantReply(this.text, {this.note});
  final String text;
  final NoteDraft? note;
}

class NoteDraft {
  const NoteDraft(this.category, this.title, this.body);
  final String category;
  final String title;
  final String body;
}

/// Answers questions about a match. [DataAssistant] works offline from the
/// data the app already loads; [ClaudeAssistant] answers anything, with web
/// search, once the user adds their own key in Settings. [history] is the
/// chat so far, oldest first, as (from the user, text).
abstract class MatchAssistant {
  String get name;
  Future<AssistantReply> ask(String question, Match match, MatchDetails details,
      {List<(bool, String)> history = const []});
}

/// Ready-made questions shown as chips in the chat.
const suggestedQuestions = [
  'Who is the favourite?',
  'How are both teams in form?',
  'Head to head record',
  'Goals trends: over 2.5 and BTTS',
  'Where are they in the table?',
  'Best odds and implied chances',
  'Line-ups and key players',
  'Latest news',
];

/// Rule-based assistant: spots what the question is about (English or
/// Spanish keywords) and builds the answer from the match data.
class DataAssistant implements MatchAssistant {
  const DataAssistant();

  @override
  String get name => 'Match data assistant';

  /// Checked in order; the first topic with a matching word wins. Words
  /// match whole tokens, or token prefixes when they end in '*'.
  static const _topics = <(String, List<String>)>[
    ('summary', ['favourite', 'favorite', 'who wins', 'who will win', 'predict*', 'pick', 'tip', 'summary', 'overview',
      'value', 'should i bet', 'favorito', 'quién gana', 'quien gana', 'pronóstico', 'pronostico', 'predicción',
      'prediccion', 'resumen', 'valor', 'apuesta']),
    ('odds', ['odds', 'price', 'prices', 'implied', 'bookmaker*', 'bookie*', 'margin', 'cuota*', 'momio*',
      'probabilidad*', 'probabilit*', 'chance*']),
    ('h2h', ['head to head', 'h2h', 'meetings', 'history', 'previous', 'last time', 'historial', 'enfrentamiento*',
      'cara a cara', 'antecedentes']),
    ('lineups', ['lineup*', 'line up*', 'starting', 'xi', 'formation*', 'player*', 'scorer*', 'injur*', 'alineaci*',
      'titulares', 'jugador*', 'goleador*', 'formaci*', 'lesion*']),
    ('form', ['form', 'streak', 'recent', 'last matches', 'last games', 'momentum', 'forma', 'racha', 'últimos',
      'ultimos']),
    ('goals', ['goal*', 'over', 'under', 'btts', 'both teams', 'score', 'scoring', 'gol', 'goles', 'ambos marcan',
      'marcan']),
    ('table', ['table', 'standing*', 'position', 'rank*', 'points', 'league', 'tabla', 'posición', 'posicion',
      'clasificaci*', 'puntos']),
    ('stats', ['stats', 'statistic*', 'possession', 'shots', 'corners', 'cards', 'estadística*', 'estadistica*',
      'posesión', 'posesion', 'tiros', 'córners', 'tarjetas']),
    ('news', ['news', 'headline*', 'article*', 'noticia*']),
  ];

  /// The topic of a question, or null when nothing matches.
  static String? topicOf(String question) {
    final q = ' ${question.toLowerCase().replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), ' ')} ';
    for (final (topic, words) in _topics) {
      for (final w in words) {
        final hit = w.endsWith('*') ? q.contains(' ${w.substring(0, w.length - 1)}') : q.contains(' $w ');
        if (hit) return topic;
      }
    }
    return null;
  }

  @override
  Future<AssistantReply> ask(String question, Match match, MatchDetails details,
      {List<(bool, String)> history = const []}) async {
    final m = match, d = details;
    // A question naming one team gets that team's form and table position.
    final team = _teamIn(question, m);
    final topic = topicOf(question) ?? (team != null ? 'form' : null);
    return switch (topic) {
      'summary' => _summary(m, d),
      'odds' => _odds(m, d),
      'goals' => _goals(m, d),
      'h2h' => _h2h(m, d),
      'form' => _form(m, d, only: team),
      'table' => _table(m, d),
      'lineups' => _lineups(m, d),
      'stats' => _stats(m, d),
      'news' => _news(d),
      _ => const AssistantReply(
          "I can answer from this match's data: favourite and odds, form, head to head, goals trends "
          '(over/under, both teams to score), the table, line-ups, stats and news. Try one of the suggestions, '
          'or add an AI key in Settings so I can answer anything with help from the web.'),
    };
  }

  static String? _teamIn(String question, Match m) {
    final q = question.toLowerCase();
    for (final t in [m.home, m.away]) {
      final words = {t.name.toLowerCase(), t.shortName.toLowerCase(), ...t.name.toLowerCase().split(' ').where((w) => w.length > 4)};
      if (words.any(q.contains)) return t.name;
    }
    return null;
  }

  static AssistantReply _reply(String category, String title, List<String> lines) {
    final body = lines.where((l) => l.isNotEmpty).join('\n');
    return AssistantReply(body, note: NoteDraft(category, title, body));
  }

  static AssistantReply _none(String what) => AssistantReply("There's no $what in the feed for this match yet.");

  // ------------------------------------------------------------ Odds

  /// Best price per outcome across bookmakers, with the margin removed.
  static ({double? home, double? draw, double? away, double margin})? bestOdds(Match m, MatchDetails d) {
    final books = d.odds.isNotEmpty ? d.odds : [if (m.odds != null) m.odds!];
    double? best(double? Function(MatchOdds) f) {
      double? out;
      for (final b in books) {
        final v = f(b);
        if (v != null && (out == null || v > out)) out = v;
      }
      return out;
    }

    final h = best((o) => o.home), x = best((o) => o.draw), a = best((o) => o.away);
    if (h == null || a == null) return null;
    final sum = 1 / h + 1 / a + (x == null ? 0 : 1 / x);
    return (home: h, draw: x, away: a, margin: sum - 1);
  }

  static String _pct(double v) => '${(v * 100).round()}%';
  static String _price(double v) => v.toStringAsFixed(2);

  static AssistantReply _odds(Match m, MatchDetails d) {
    final b = bestOdds(m, d);
    if (b == null) return _none('odds');
    final total = 1 + b.margin;
    final books = d.odds.isNotEmpty ? d.odds : [if (m.odds != null) m.odds!];
    final ou = books.where((o) => o.totalLine != null && o.over != null && o.under != null).firstOrNull;
    return _reply('Odds', 'Best odds and implied chances', [
      'Best prices across ${books.length} bookmaker${books.length == 1 ? '' : 's'}:',
      '• ${m.home.name}: ${_price(b.home!)} (${_pct(1 / b.home! / total)})',
      if (b.draw != null) '• Draw: ${_price(b.draw!)} (${_pct(1 / b.draw! / total)})',
      '• ${m.away.name}: ${_price(b.away!)} (${_pct(1 / b.away! / total)})',
      'Bookmaker margin: ${(b.margin * 100).toStringAsFixed(1)}%.',
      if (ou != null)
        'Total goals ${_line(ou.totalLine!)}: over ${_price(ou.over!)}, under ${_price(ou.under!)} (${ou.provider}).',
    ]);
  }

  static String _line(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  // ------------------------------------------------------------ Form and goals

  /// Record and goals from a team's last games (also used by the parlay check).
  static ({int w, int dr, int l, int gf, int ga, int over25, int btts, int games}) recentOf(TeamInfo t) => _recent(t);

  /// Table position and points of a team, e.g. ('#5', '10').
  static (String, String)? positionOf(MatchDetails d, TeamInfo t) => _position(d, t);

  static ({int w, int dr, int l, int gf, int ga, int over25, int btts, int games}) _recent(TeamInfo t) {
    var w = 0, dr = 0, l = 0, gf = 0, ga = 0, over = 0, btts = 0, games = 0;
    for (final g in t.lastGames) {
      final p = g.score.split('-').map((s) => int.tryParse(s.trim())).toList();
      if (p.length != 2 || p[0] == null || p[1] == null) continue;
      final hi = p[0]! > p[1]! ? p[0]! : p[1]!, lo = p[0]! > p[1]! ? p[1]! : p[0]!;
      games++;
      switch (g.result) {
        case 'W':
          w++;
          gf += hi;
          ga += lo;
        case 'L':
          l++;
          gf += lo;
          ga += hi;
        default:
          dr++;
          gf += hi;
          ga += lo;
      }
      if (hi + lo > 2) over++;
      if (lo > 0) btts++;
    }
    return (w: w, dr: dr, l: l, gf: gf, ga: ga, over25: over, btts: btts, games: games);
  }

  static AssistantReply _form(Match m, MatchDetails d, {String? only}) {
    final teams = [(m.home.name, d.home), (m.away.name, d.away)].where((t) => only == null || t.$1 == only).toList();
    if (teams.every((t) => t.$2.form.isEmpty && t.$2.lastGames.isEmpty)) return _none('recent form');
    final lines = <String>[];
    for (final (name, t) in teams) {
      final r = _recent(t);
      final form = t.form.isNotEmpty ? t.form : t.lastGames.reversed.map((g) => g.result).join();
      final pos = _position(d, t);
      lines.add('$name: ${form.split('').join(' ')} (latest first)'
          '${r.games > 0 ? ', ${r.w * 3 + r.dr} pts from last ${r.games}, goals ${r.gf}-${r.ga}' : ''}'
          '${pos != null ? '; ${pos.$1} in the table on ${pos.$2} pts' : ''}.');
    }
    return _reply('Form', only == null ? 'Recent form' : '$only form', lines);
  }

  static AssistantReply _goals(Match m, MatchDetails d) {
    final h = _recent(d.home), a = _recent(d.away);
    if (h.games == 0 && a.games == 0 && d.h2h.isEmpty) return _none('goals data');
    String team(String name, ({int w, int dr, int l, int gf, int ga, int over25, int btts, int games}) r) => r.games == 0
        ? ''
        : '$name: scores ${(r.gf / r.games).toStringAsFixed(1)} and concedes ${(r.ga / r.games).toStringAsFixed(1)} '
            'a game; over 2.5 in ${r.over25}/${r.games}, both scored in ${r.btts}/${r.games}.';
    final h2hGoals = [
      for (final g in d.h2h)
        if (g.score.split('-').map((s) => int.tryParse(s.trim())).toList() case [final x?, final y?]) (x, y)
    ];
    return _reply('Goals', 'Goals trends', [
      'Last matches:',
      team(m.home.name, h),
      team(m.away.name, a),
      if (h2hGoals.isNotEmpty)
        'Head to head: ${(h2hGoals.fold<int>(0, (s, g) => s + g.$1 + g.$2) / h2hGoals.length).toStringAsFixed(1)} '
            'goals a game, both scored in ${h2hGoals.where((g) => g.$1 > 0 && g.$2 > 0).length}/${h2hGoals.length}.',
    ]);
  }

  // ------------------------------------------------------------ H2H, table

  static AssistantReply _h2h(Match m, MatchDetails d) {
    if (d.h2h.isEmpty) return _none('head-to-head record');
    return _reply('H2H', 'Head to head', [
      if (d.h2hSummary.isNotEmpty) '${d.h2hSummary}.',
      'Last meetings:',
      for (final g in d.h2h.take(5))
        '• ${g.date == null ? '' : '${g.date!.year}-${g.date!.month.toString().padLeft(2, '0')}  '}${g.home} ${g.score} ${g.away}',
    ]);
  }

  static (String, String)? _position(MatchDetails d, TeamInfo t) {
    for (final r in d.table) {
      if ((t.id.isNotEmpty && r.teamId == t.id) || r.team == t.name) return ('#${r.rank}', r.points);
    }
    return null;
  }

  static AssistantReply _table(Match m, MatchDetails d) {
    if (d.table.isEmpty) return _none('league table');
    final lines = <String>[];
    for (final (name, t) in [(m.home.name, d.home), (m.away.name, d.away)]) {
      final r = d.table.where((r) => (t.id.isNotEmpty && r.teamId == t.id) || r.team == t.name).firstOrNull;
      if (r == null) continue;
      lines.add('$name: #${r.rank}, ${r.points} pts from ${r.played} (W${r.won} D${r.drawn} L${r.lost}), GD ${r.goalDiff}.');
    }
    if (lines.isEmpty) return _none('table position for these teams');
    return _reply('Table', 'League table', [if (d.tableTitle.isNotEmpty) '${d.tableTitle}:', ...lines]);
  }

  // ------------------------------------------------------------ Line-ups, stats, news

  static AssistantReply _lineups(Match m, MatchDetails d) {
    final lines = <String>[];
    for (final (name, t) in [(m.home.name, d.home), (m.away.name, d.away)]) {
      if (t.starters.isNotEmpty) {
        lines.add('$name (${t.formation ?? 'line-up'}): ${t.starters.map((p) => p.name).join(', ')}.');
      }
      final top = t.leaders.take(2).map((l) => '${l.$2} (${l.$1.toLowerCase()} ${l.$3})').join(', ');
      if (top.isNotEmpty) lines.add('$name key players: $top.');
    }
    if (lines.isEmpty) return _none('line-up or player data');
    if (d.home.starters.isEmpty && d.away.starters.isEmpty) {
      lines.insert(0, 'Line-ups are not out yet (usually about an hour before kick-off).');
    }
    return _reply('Line-ups', 'Line-ups and key players', lines);
  }

  static AssistantReply _stats(Match m, MatchDetails d) {
    if (d.stats.isEmpty) return _none('stats');
    return _reply('Stats', d.statsAreSeason ? 'Season stats' : 'Match stats', [
      '${m.home.name} vs ${m.away.name}${d.statsAreSeason ? ' (season so far)' : ''}:',
      for (final (label, h, a) in d.stats.take(10)) '• $label: $h - $a',
    ]);
  }

  static AssistantReply _news(MatchDetails d) {
    if (d.news.isEmpty) return _none('news');
    return _reply('News', 'Latest news', [for (final n in d.news.take(3)) '• ${n.headline}']);
  }

  // ------------------------------------------------------------ Summary

  static AssistantReply _summary(Match m, MatchDetails d) {
    final lines = <String>[];
    final b = bestOdds(m, d);
    if (b != null) {
      final total = 1 + b.margin;
      final ph = 1 / b.home! / total, pa = 1 / b.away! / total;
      final fav = ph >= pa ? m.home.name : m.away.name;
      lines.add('Market favourite: $fav (${_pct(ph >= pa ? ph : pa)} implied, '
          '${m.home.name} ${_price(b.home!)}${b.draw != null ? ' / draw ${_price(b.draw!)}' : ''} / ${m.away.name} ${_price(b.away!)}).');
    }
    final h = _recent(d.home), a = _recent(d.away);
    if (h.games > 0 && a.games > 0) {
      final hp = h.w * 3 + h.dr, ap = a.w * 3 + a.dr;
      lines.add('Form: ${m.home.name} $hp pts from ${h.games}, ${m.away.name} $ap pts from ${a.games}'
          '${hp == ap ? ' (level).' : ' (edge ${hp > ap ? m.home.name : m.away.name}).'}');
      final games = h.games + a.games;
      lines.add('Goals: over 2.5 in ${h.over25 + a.over25}/$games recent games, both scored in ${h.btts + a.btts}/$games.');
    }
    final hpos = _position(d, d.home), apos = _position(d, d.away);
    if (hpos != null && apos != null) lines.add('Table: ${m.home.name} ${hpos.$1}, ${m.away.name} ${apos.$1}.');
    if (d.h2hSummary.isNotEmpty) lines.add('Head to head: ${d.h2hSummary}.');
    if (lines.isEmpty) return _none('data to summarise');
    lines.add('This is a summary of the data, not a guarantee.');
    return _reply('Summary', 'Match summary', lines);
  }
}
