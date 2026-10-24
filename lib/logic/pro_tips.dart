import 'dart:math' as math;

import '../data/fixtures.dart';

/// How sure a tip is. The price of a Pro tip follows from it.
enum Confidence {
  max('Max', 75),
  high('High', 62),
  medium('Medium', 0);

  const Confidence(this.label, this.from);
  final String label;

  /// Lowest chance, in percent, for this level.
  final int from;

  /// Tokens to unlock a Pro tip at this level. Safer tips cost more; a tip
  /// that loses gives its tokens back.
  int get cost => switch (this) {
        Confidence.max => 3,
        Confidence.high => 2,
        Confidence.medium => 1,
      };

  static Confidence of(double chance) =>
      Confidence.values.firstWhere((c) => chance * 100 >= c.from, orElse: () => Confidence.medium);
}

/// The markets a tip can be on, each settled from the final score.
enum TipMarket {
  homeWin,
  draw,
  awayWin,
  homeOrDraw,
  awayOrDraw,
  over15,
  over25,
  under25,
  under35,
  bttsYes,
  bttsNo,
  homeScores,
  awayScores,
  overLine,
  underLine;

  /// Whether the tip won with this final score; [line] is the totals line
  /// for [overLine] and [underLine].
  bool wins(int h, int a, {double? line}) => switch (this) {
        homeWin => h > a,
        draw => h == a,
        awayWin => a > h,
        homeOrDraw => h >= a,
        awayOrDraw => a >= h,
        over15 => h + a > 1.5,
        over25 => h + a > 2.5,
        under25 => h + a < 2.5,
        under35 => h + a < 3.5,
        bttsYes => h > 0 && a > 0,
        bttsNo => h == 0 || a == 0,
        homeScores => h > 0,
        awayScores => a > 0,
        overLine => line != null && h + a > line,
        underLine => line != null && h + a < line,
      };

  String get group => switch (this) {
        homeWin || draw || awayWin => 'Match result',
        homeOrDraw || awayOrDraw => 'Double chance',
        over15 || over25 || under25 || under35 || overLine || underLine => 'Total',
        bttsYes || bttsNo => 'Both teams to score',
        homeScores || awayScores => 'Team to score',
      };
}

/// One prediction for a match. [free] tips show in Daily tips; the rest are
/// Pro tips that cost [cost] tokens to unlock.
class Tip {
  const Tip({
    required this.matchId,
    required this.market,
    required this.pick,
    required this.chance,
    required this.reasons,
    required this.free,
    this.line,
  });
  final String matchId;
  final TipMarket market;

  /// What to back, e.g. "Over 1.5 goals".
  final String pick;

  /// The model's chance that the tip wins, 0-1.
  final double chance;
  final List<String> reasons;
  final bool free;
  final double? line;

  String get id => '$matchId:${market.name}';
  Confidence get confidence => Confidence.of(chance);
  int get cost => confidence.cost;
  int get percent => (chance * 100).round();

  /// The decimal odds the chance is worth.
  double get fairOdds => 1 / chance;

  /// Won (true), lost (false) or not decided yet (null).
  bool? result(int? h, int? a) => h == null || a == null ? null : market.wins(h, a, line: line);
}

/// Today's tips for a match: a couple of free ones and the Pro tips.
class MatchTips {
  const MatchTips({required this.daily, required this.pro});
  final List<Tip> daily;
  final List<Tip> pro;

  List<Tip> get all => [...daily, ...pro];
}

/// Simulated tips while the prediction model is built: chances start from the
/// bookmaker's prices when there are any, the match's form and table nudge
/// them, and a seed from the match id keeps the same tips on every visit.
MatchTips simulateTips(Match match, MatchDetails details) {
  final rnd = math.Random(match.id.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x3fffffff));
  final soccer = match.league.knownSport == Sport.soccer;
  final book = [...details.odds, ?match.odds].where((o) => o.home != null && o.away != null).firstOrNull;

  // Win chances: the bookmaker's, margin removed, or a home-leaning guess.
  double pH, pD, pA;
  if (book != null) {
    final ih = 1 / book.home!, ia = 1 / book.away!, id = book.draw == null ? 0.0 : 1 / book.draw!;
    final sum = ih + ia + id;
    pH = ih / sum;
    pA = ia / sum;
    pD = id / sum;
  } else {
    pD = soccer ? 0.22 + rnd.nextDouble() * 0.08 : 0;
    pH = (1 - pD) * (0.45 + rnd.nextDouble() * 0.25);
    pA = 1 - pD - pH;
  }
  // Form over the last five nudges each side a little.
  double formScore(String f) => f.isEmpty
      ? 0
      : f.split('').map((c) => c == 'W' ? 1.0 : c == 'L' ? -1.0 : 0.0).reduce((a, b) => a + b) / f.length;
  final nudge = (formScore(details.home.form) - formScore(details.away.form)) * 0.03;
  pH = (pH + nudge).clamp(0.05, 0.9);
  pA = (pA - nudge).clamp(0.05, 0.9);
  final norm = pH + pD + pA;
  pH /= norm;
  pD /= norm;
  pA /= norm;

  final home = match.home.name, away = match.away.name;
  final reasons = _reasons(match, details);
  final candidates = <(TipMarket, String, double, double?)>[
    (TipMarket.homeWin, '$home to win', pH, null),
    (TipMarket.awayWin, '$away to win', pA, null),
  ];
  if (soccer) {
    // Goals: ESPN's over price when there is one, otherwise around 2.6 a game.
    var over25 = book?.over != null && book?.under != null && book?.totalLine == 2.5
        ? (1 / book!.over!) / (1 / book.over! + 1 / book.under!)
        : 0.45 + rnd.nextDouble() * 0.14;
    over25 = over25.clamp(0.3, 0.72);
    final btts = (0.42 + rnd.nextDouble() * 0.16 + (over25 - 0.5) * 0.4).clamp(0.3, 0.7);
    candidates.addAll([
      (TipMarket.draw, 'Draw', pD, null),
      (TipMarket.homeOrDraw, '$home or draw', pH + pD, null),
      (TipMarket.awayOrDraw, '$away or draw', pA + pD, null),
      (TipMarket.over15, 'Over 1.5 goals', (over25 + 0.25).clamp(0.55, 0.88), null),
      (TipMarket.over25, 'Over 2.5 goals', over25, null),
      (TipMarket.under25, 'Under 2.5 goals', 1 - over25, null),
      (TipMarket.under35, 'Under 3.5 goals', (1 - over25 + 0.22).clamp(0.5, 0.86), null),
      (TipMarket.bttsYes, 'Both teams to score', btts, null),
      (TipMarket.bttsNo, 'Not both teams to score', 1 - btts, null),
      (TipMarket.homeScores, '$home to score', (0.6 + pH * 0.4).clamp(0.55, 0.9), null),
      (TipMarket.awayScores, '$away to score', (0.55 + pA * 0.4).clamp(0.5, 0.88), null),
    ]);
  } else if (book?.totalLine case final line?) {
    final over = book!.over != null && book.under != null ? (1 / book.over!) / (1 / book.over! + 1 / book.under!) : 0.5;
    final unit = match.league.knownSport.scoreUnit;
    candidates.addAll([
      (TipMarket.overLine, 'Over $line $unit', over, line),
      (TipMarket.underLine, 'Under $line $unit', 1 - over, line),
    ]);
  }

  // Tips that can both win together only: never a market and its opposite.
  const opposite = {
    TipMarket.over25: TipMarket.under25,
    TipMarket.under25: TipMarket.over25,
    TipMarket.bttsYes: TipMarket.bttsNo,
    TipMarket.bttsNo: TipMarket.bttsYes,
    TipMarket.overLine: TipMarket.underLine,
    TipMarket.underLine: TipMarket.overLine,
    TipMarket.homeWin: TipMarket.awayOrDraw,
    TipMarket.awayWin: TipMarket.homeOrDraw,
    TipMarket.homeOrDraw: TipMarket.awayWin,
    TipMarket.awayOrDraw: TipMarket.homeWin,
  };
  final used = <TipMarket>{};
  Tip? take(double target, {required bool free, double min = 0.3}) {
    final open = candidates
        .where((c) => c.$3 >= min && !used.contains(c.$1) && !used.contains(opposite[c.$1]))
        .toList()
      ..sort((a, b) => (a.$3 - target).abs().compareTo((b.$3 - target).abs()));
    final c = open.firstOrNull;
    if (c == null) return null;
    used.add(c.$1);
    return Tip(
      matchId: match.id,
      market: c.$1,
      pick: c.$2,
      chance: c.$3,
      line: c.$4,
      free: free,
      reasons: [..._marketReason(c.$1, c.$3, home, away), ...reasons],
    );
  }

  // The Pro tips first, one at each level where the match allows it.
  final pro = [take(0.8, free: false, min: 0.62), take(0.68, free: false, min: 0.5), take(0.56, free: false)]
      .nonNulls
      .toList()
    ..sort((a, b) => b.chance.compareTo(a.chance));
  final daily = [take(0.6, free: true), take(0.5, free: true)].nonNulls.toList();
  return MatchTips(daily: daily, pro: pro);
}

List<String> _marketReason(TipMarket m, double p, String home, String away) => [
      switch (m) {
        TipMarket.homeWin => '$home win this ${(p * 100).round()}% of the time in our simulation.',
        TipMarket.awayWin => '$away come out on top in ${(p * 100).round()}% of simulated games.',
        TipMarket.draw => 'An even game: the sides are close on the prices.',
        TipMarket.homeOrDraw => '$home avoid defeat in ${(p * 100).round()}% of simulated games.',
        TipMarket.awayOrDraw => '$away avoid defeat in ${(p * 100).round()}% of simulated games.',
        TipMarket.over15 || TipMarket.over25 || TipMarket.overLine => 'Both attacks point to an open game.',
        TipMarket.under25 || TipMarket.under35 || TipMarket.underLine => 'A tight, low-scoring game is the likeliest script.',
        TipMarket.bttsYes => 'Each side scores often and concedes often.',
        TipMarket.bttsNo => 'At least one side struggles to score.',
        TipMarket.homeScores => '$home rarely go a home game without a goal.',
        TipMarket.awayScores => '$away find the net in most of their games.',
      },
    ];

/// Facts from the match feed behind every tip: form and table places.
List<String> _reasons(Match match, MatchDetails d) {
  final out = <String>[];
  for (final (t, info) in [(match.home, d.home), (match.away, d.away)]) {
    final pos = d.table
        .where((r) => (info.id.isNotEmpty && r.teamId == info.id) || r.team == t.name)
        .firstOrNull;
    final parts = [
      if (info.form.isNotEmpty) 'form ${info.form.split('').join(' ')}',
      if (pos != null) '${pos.rank}${_suffix(pos.rank)} in the table${pos.points.isEmpty ? '' : ' on ${pos.points} pts'}',
    ];
    if (parts.isNotEmpty) out.add('${t.name}: ${parts.join(', ')}.');
  }
  return out;
}

String _suffix(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return 'th';
  return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

/// A Pro tip the user paid for. [result] is 'won' or 'refunded' once the
/// match is over.
class UnlockedTip {
  const UnlockedTip({required this.cost, required this.at, this.result});
  final int cost;
  final String at;
  final String? result;

  UnlockedTip settled(String result) => UnlockedTip(cost: cost, at: at, result: result);

  Map<String, dynamic> toJson() => {'cost': cost, 'at': at, 'result': ?result};

  factory UnlockedTip.fromJson(Map<String, dynamic> j) =>
      UnlockedTip(cost: (j['cost'] as num?)?.toInt() ?? 0, at: '${j['at'] ?? ''}', result: j['result'] as String?);
}
