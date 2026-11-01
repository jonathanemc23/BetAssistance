import '../l10n/l10n.dart';

/// Bet markets the user can pick from when the match list has no price for
/// them (handicaps, corners, cards...). Each one turns a side and a line into
/// the selection text saved with the bet, e.g. "Arsenal -1.5" or
/// "Over 9.5 corners".
class Market {
  const Market(this.id, this.label, {this.line, this.step = 1, this.signedLine = false, this.input});
  final String id;
  final String label;

  /// Default line for markets that have one (2.5 goals, 9.5 corners...).
  final double? line;
  final double step;

  /// Handicaps show the line with its sign (+0.5, -1.5).
  final bool signedLine;

  /// Hint for markets that take free text (a score, a player).
  final String? input;

  /// [label] in the app's language.
  String get name => switch (id) {
        'result' => tr('Match result'),
        'double_chance' => tr('Double chance'),
        'handicap' => tr('Handicap'),
        'goals' => tr('Over/Under goals'),
        'btts' => tr('Both teams to score'),
        'corners' => tr('Corners'),
        'cards' => tr('Cards'),
        'dnb' => tr('Draw no bet'),
        'half_time' => tr('Half-time result'),
        'correct_score' => tr('Correct score'),
        'scorer' => tr('Goalscorer'),
        'team_goals' => tr('Team total'),
        'win_to_nil' => tr('Win to nil'),
        'other' => tr('Other'),
        _ => label,
      };

  /// [input] in the app's language.
  String? get hint => switch (id) {
        'correct_score' => tr('Score, e.g. 2-1'),
        'scorer' => tr('Player, e.g. Haaland'),
        'other' => tr('Your pick, e.g. Arsenal win both halves'),
        _ => input,
      };

  bool get hasLine => line != null;
  bool get hasText => input != null;

  /// The sides to choose from for a match between [home] and [away]. Sports
  /// without draws ([draws] false) only offer the two teams for a result.
  List<String> sides(String home, String away, {bool draws = true}) => switch (id) {
        'result' || 'half_time' => [home, if (draws) 'Draw', away],
        'double_chance' => ['$home or draw', '$home or $away', '$away or draw'],
        'dnb' || 'handicap' || 'win_to_nil' => [home, away],
        'team_goals' => ['$home over', '$home under', '$away over', '$away under'],
        'goals' || 'corners' || 'cards' => ['Over', 'Under'],
        'btts' => ['Yes', 'No'],
        _ => const [],
      };

  /// The selection text for a side, line and free text. [unit] is what the
  /// totals count: goals, points or runs.
  String selection({String? side, double? line, String text = '', String unit = 'goals'}) {
    final t = text.trim();
    final l = line == null ? '' : formatLine(line, signed: signedLine);
    return switch (id) {
      'result' => side == 'Draw' ? 'Draw' : '$side to win',
      'double_chance' => side ?? '',
      'dnb' => '$side draw no bet',
      'handicap' => '$side $l',
      'goals' => '$side $l $unit',
      'team_goals' => '$side $l $unit',
      'win_to_nil' => '$side to win to nil',
      'corners' => '$side $l corners',
      'cards' => '$side $l cards',
      'btts' => 'Both teams to score: $side',
      'half_time' => 'Half-time: ${side == 'Draw' ? 'Draw' : '$side to win'}',
      'correct_score' => 'Correct score $t',
      'scorer' => '$t to score',
      _ => t,
    };
  }
}

const markets = <Market>[
  Market('result', 'Match result'),
  Market('double_chance', 'Double chance'),
  Market('handicap', 'Handicap', line: -0.5, step: 0.25, signedLine: true),
  Market('goals', 'Over/Under goals', line: 2.5),
  Market('btts', 'Both teams to score'),
  Market('corners', 'Corners', line: 9.5),
  Market('cards', 'Cards', line: 4.5),
  Market('dnb', 'Draw no bet'),
  Market('half_time', 'Half-time result'),
  Market('correct_score', 'Correct score', input: 'Score, e.g. 2-1'),
  Market('scorer', 'Goalscorer', input: 'Player, e.g. Haaland'),
  Market('team_goals', 'Team total', line: 1.5),
  Market('win_to_nil', 'Win to nil'),
  Market('other', 'Other', input: 'Your pick, e.g. Arsenal win both halves'),
];

/// The markets that make sense for [sport] ('soccer', 'basketball',
/// 'baseball'), most used first. Football gets them all; the others have no
/// draws, corners or cards.
List<Market> marketsFor(String sport) {
  if (sport == 'soccer') {
    const order = ['result', 'double_chance', 'handicap', 'goals', 'btts', 'dnb', 'team_goals', 'win_to_nil'];
    return [for (final id in order) marketById(id), for (final m in markets) if (!order.contains(m.id)) m];
  }
  final line = sport == 'basketball' ? (-5.5, 220.5, 110.5, 0.5) : (-1.5, 8.5, 4.5, 0.5);
  return [
    marketById('result'),
    Market('handicap', 'Handicap', line: line.$1, step: line.$4, signedLine: true),
    Market('goals', 'Over/Under goals', line: line.$2, step: line.$4),
    Market('team_goals', 'Team total', line: line.$3, step: line.$4),
    marketById('other'),
  ];
}

/// Markets [gradePick] can settle from the final score alone. Picks in the
/// others (corners, cards, scorers, half-time) are marked by the user.
const scoreSettled = {'result', 'double_chance', 'dnb', 'handicap', 'goals', 'btts', 'correct_score', 'team_goals', 'win_to_nil'};

Market marketById(String? id) => markets.firstWhere((m) => m.id == id, orElse: () => markets.last);

String formatLine(double v, {bool signed = false}) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : '${double.parse(v.toStringAsFixed(2))}';
  return signed && v > 0 ? '+$s' : s;
}

/// Home and away team names from an event like "Arsenal vs Chelsea".
(String, String) teamsOf(String event) {
  final parts = event.split(RegExp(r'\s+(?:vs\.?|v|-|x)\s+', caseSensitive: false));
  if (parts.length == 2 && parts.every((p) => p.trim().isNotEmpty)) return (parts[0].trim(), parts[1].trim());
  return ('Home', 'Away');
}

/// The market a selection belongs to, worked out from its text. Used for
/// bets logged before markets existed and for picks typed by hand.
String marketOf(String selection) {
  final s = selection.toLowerCase().trim();
  bool has(String p) => RegExp(p).hasMatch(s);
  if (has(r'corner')) return 'corners';
  if (has(r'\bcards?\b|booking')) return 'cards';
  if (has(r'both teams|btts|ambos')) return 'btts';
  if (has(r'half[- ]?time|^ht\b|1st half|first half')) return 'half_time';
  if (has(r'correct score|^\d+\s*-\s*\d+$')) return 'correct_score';
  if (has(r'draw no bet|\bdnb\b')) return 'dnb';
  if (has(r'^(over|under|o|u)\s*\d')) return 'goals';
  if (has(r'.\s(over|under)\s+\d+(\.\d+)?\s*(goals?|points?|runs?)?$')) return 'team_goals';
  if (has(r'to nil$')) return 'win_to_nil';
  if (has(r'\bor draw\b|\bor\b.*\bor\b|^(1x|x2|12)$| or ')) return 'double_chance';
  if (has(r'to score|anytime|scorer')) return 'scorer';
  if (has(r'[+-]\d+(\.\d+)?\s*$|handicap|spread|\bah\b')) return 'handicap';
  if (s == 'draw' || has(r'to win|\bml\b|moneyline|^(1|x|2)$')) return 'result';
  return 'other';
}
