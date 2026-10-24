import 'dart:math' as math;

import '../data/fixtures.dart';
import '../l10n/l10n.dart';

/// How sure a tip is, and the price of a Pro tip at that level.
enum Confidence {
  max('Max'),
  high('High'),
  medium('Medium');

  const Confidence(this.label);
  final String label;

  /// [label] in the app's language.
  String get title => switch (this) {
        Confidence.max => tr('Max'),
        Confidence.high => tr('High'),
        Confidence.medium => tr('Medium'),
      };

  /// Tokens to unlock a Pro tip at this level. Safer tips cost more; a tip
  /// that loses gives its tokens back.
  int get cost => switch (this) {
        Confidence.max => 3,
        Confidence.high => 2,
        Confidence.medium => 1,
      };

  /// Lowest decimal odds a Pro tip at this level may have: the more a tip
  /// costs, the better its price. Every tip stays at [proMaxOdds] or under.
  double get minOdds => this == Confidence.max ? 1.8 : 1.6;

  /// The level for a free tip, from its chance.
  static Confidence of(double chance) => chance >= 0.6
      ? Confidence.max
      : chance >= 0.5
          ? Confidence.high
          : Confidence.medium;
}

/// The odds rules, by what the tip costs: free tips between 1.4 and 2.0,
/// Medium and High (1 and 2 tokens) between 1.6 and 2.0, and Max (3 tokens)
/// between 1.8 and 2.0. A Pro tip may be two selections whose combined odds
/// fit its range.
const freeMinOdds = 1.4, freeMaxOdds = 2.0, proMaxOdds = 2.0;

bool followsOddsRules(Tip t) => t.free
    ? t.legs.length == 1 && t.odds >= freeMinOdds && t.odds <= freeMaxOdds
    : t.legs.isNotEmpty && t.legs.length <= 2 && t.odds >= t.level.minOdds && t.odds <= proMaxOdds;

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
        homeWin || draw || awayWin => tr('Match result'),
        homeOrDraw || awayOrDraw => tr('Double chance'),
        over15 || over25 || under25 || under35 || overLine || underLine => tr('Total'),
        bttsYes || bttsNo => tr('Both teams to score'),
        homeScores || awayScores => tr('Team to score'),
      };
}

/// One selection of a tip, with the price it is offered at.
class TipLeg {
  const TipLeg(this.market, this.pick, this.odds, {this.line});
  final TipMarket market;

  /// What to back, e.g. "Over 1.5 goals".
  final String pick;
  final double odds;
  final double? line;

  Map<String, dynamic> toJson() => {'market': market.name, 'pick': pick, 'odds': odds, 'line': ?line};

  static TipLeg? fromJson(Map<String, dynamic> j) {
    final m = TipMarket.values.where((m) => m.name == j['market']).firstOrNull;
    if (m == null) return null;
    return TipLeg(m, '${j['pick'] ?? ''}', (j['odds'] as num?)?.toDouble() ?? 0, line: (j['line'] as num?)?.toDouble());
  }
}

/// One prediction for a match: a single, or two selections on the same
/// match. [free] tips show in Daily tips; the rest are Pro tips that cost
/// [cost] tokens to unlock.
class Tip {
  const Tip({
    required this.matchId,
    required this.legs,
    required this.chance,
    required this.reasons,
    required this.free,
    required this.level,
  });
  final String matchId;
  final List<TipLeg> legs;

  /// The model's chance that the tip wins, 0-1.
  final double chance;
  final List<String> reasons;
  final bool free;
  final Confidence level;

  String get id => '$matchId:${legs.map((l) => l.market.name).join('+')}';
  bool get isCombo => legs.length > 1;
  TipMarket get market => legs.first.market;
  String get pick => legs.map((l) => l.pick).join(' & ');
  String get group => isCombo ? tr('Bet builder · {n} selections', {'n': legs.length}) : market.group;
  Confidence get confidence => level;
  int get cost => level.cost;
  int get percent => (chance * 100).round();

  /// The decimal odds of the tip: both prices multiplied for two selections.
  double get odds => legs.fold(1.0, (o, l) => o * l.odds);

  /// What the model expects back per unit staked above the stake: positive
  /// is a value bet.
  double get value => chance * odds - 1;

  /// Won (true), lost (false) or not decided yet (null).
  bool? result(int? h, int? a) =>
      h == null || a == null ? null : legs.every((l) => l.market.wins(h, a, line: l.line));

  Map<String, dynamic> toJson() => {
        'match': matchId,
        'legs': [for (final l in legs) l.toJson()],
        'chance': chance,
        'reasons': reasons,
        'free': free,
        'level': level.name,
      };

  static Tip? fromJson(Map<String, dynamic> j) {
    try {
      final legs = [for (final l in (j['legs'] as List)) ?TipLeg.fromJson((l as Map).cast<String, dynamic>())];
      if (legs.isEmpty) return null;
      return Tip(
        matchId: '${j['match']}',
        legs: legs,
        chance: (j['chance'] as num).toDouble(),
        reasons: [for (final r in (j['reasons'] as List? ?? const [])) '$r'],
        free: j['free'] == true,
        level: Confidence.values.firstWhere((c) => c.name == j['level'], orElse: () => Confidence.medium),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Today's tips for a match: a couple of free ones and the Pro tips.
class MatchTips {
  const MatchTips({required this.daily, required this.pro});
  final List<Tip> daily;
  final List<Tip> pro;

  List<Tip> get all => [...daily, ...pro];

  /// These tips with the ones already bought for the match in their place:
  /// a bought tip stays what was paid for even when the prices move.
  MatchTips withBought(Iterable<Tip> bought) {
    final pro = [...this.pro];
    for (final b in bought) {
      if (pro.any((t) => t.id == b.id)) continue;
      final i = pro.indexWhere((t) => t.level == b.level);
      if (i >= 0) {
        pro[i] = b;
      } else {
        pro.add(b);
      }
    }
    return MatchTips(daily: daily, pro: pro);
  }
}

/// Simulated tips while the prediction model is built. Each market gets a
/// price (the bookmaker's when the feed has one, otherwise a fair price with
/// a usual margin) and a model chance a few points above what the price
/// implies, so every tip is a value bet. The odds rules then pick the tips:
/// see [followsOddsRules]. Only the match list's prices and a seed from the
/// match id go in, so the tips are the same on every page and every visit;
/// [details] only adds the reasons.
MatchTips simulateTips(Match match, MatchDetails details) {
  final rnd = math.Random(match.id.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0x3fffffff));
  final soccer = match.league.knownSport == Sport.soccer;
  final book = [?match.odds, ...details.odds].where((o) => o.home != null && o.away != null).firstOrNull;

  // Win chances: the bookmaker's, margin removed, or a home-leaning guess.
  double pH, pD, pA;
  var margin = 0.06;
  if (book != null) {
    final ih = 1 / book.home!, ia = 1 / book.away!, id = book.draw == null ? 0.0 : 1 / book.draw!;
    final sum = ih + ia + id;
    pH = ih / sum;
    pA = ia / sum;
    pD = id / sum;
    margin = (sum - 1).clamp(0.03, 0.1);
  } else {
    pD = soccer ? 0.22 + rnd.nextDouble() * 0.08 : 0;
    pH = (1 - pD) * (0.45 + rnd.nextDouble() * 0.25);
    pA = 1 - pD - pH;
  }

  final home = match.home.name, away = match.away.name;
  // (market, pick, fair chance, line, bookmaker price if any)
  final markets = <(TipMarket, String, double, double?, double?)>[
    (TipMarket.homeWin, '$home to win', pH, null, book?.home),
    (TipMarket.awayWin, '$away to win', pA, null, book?.away),
  ];
  if (soccer) {
    // Goals: the bookmaker's over price when there is one, otherwise around 2.6 a game.
    final totals = book?.over != null && book?.under != null && book?.totalLine == 2.5;
    var over25 = totals ? (1 / book!.over!) / (1 / book.over! + 1 / book.under!) : 0.45 + rnd.nextDouble() * 0.14;
    over25 = over25.clamp(0.3, 0.72);
    final btts = (0.42 + rnd.nextDouble() * 0.16 + (over25 - 0.5) * 0.4).clamp(0.3, 0.7);
    markets.addAll([
      (TipMarket.draw, 'Draw', pD, null, book?.draw),
      (TipMarket.homeOrDraw, '$home or draw', pH + pD, null, null),
      (TipMarket.awayOrDraw, '$away or draw', pA + pD, null, null),
      (TipMarket.over15, 'Over 1.5 goals', (over25 + 0.25).clamp(0.55, 0.88), null, null),
      (TipMarket.over25, 'Over 2.5 goals', over25, null, totals ? book!.over : null),
      (TipMarket.under25, 'Under 2.5 goals', 1 - over25, null, totals ? book!.under : null),
      (TipMarket.under35, 'Under 3.5 goals', (1 - over25 + 0.22).clamp(0.5, 0.86), null, null),
      (TipMarket.bttsYes, 'Both teams to score', btts, null, null),
      (TipMarket.bttsNo, 'Not both teams to score', 1 - btts, null, null),
      (TipMarket.homeScores, '$home to score', (0.6 + pH * 0.4).clamp(0.55, 0.9), null, null),
      (TipMarket.awayScores, '$away to score', (0.55 + pA * 0.4).clamp(0.5, 0.88), null, null),
    ]);
  } else if (book?.totalLine case final line?) {
    final hasPrices = book!.over != null && book.under != null;
    final over = hasPrices ? (1 / book.over!) / (1 / book.over! + 1 / book.under!) : 0.5;
    final unit = match.league.knownSport.scoreUnit;
    markets.addAll([
      (TipMarket.overLine, 'Over $line $unit', over, line, book.over),
      (TipMarket.underLine, 'Under $line $unit', 1 - over, line, book.under),
    ]);
  }

  // Each market's price, and the model's chance: what the price implies plus
  // an edge of 3 to 12 points.
  final candidates = [
    for (final (m, pick, p, line, price) in markets)
      if (p > 0)
        () {
          final odds = price ?? double.parse((1 / (p * (1 + margin))).clamp(1.01, 50.0).toStringAsFixed(2));
          final edge = 0.03 + rnd.nextDouble() * 0.09;
          return (leg: TipLeg(m, pick, odds, line: line), chance: math.min(0.95, (1 / odds) * (1 + edge)));
        }(),
  ];

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
  // Markets that already win whenever the key wins: never paired with it.
  const implies = {
    TipMarket.homeWin: {TipMarket.homeOrDraw, TipMarket.homeScores},
    TipMarket.awayWin: {TipMarket.awayOrDraw, TipMarket.awayScores},
    TipMarket.draw: {TipMarket.homeOrDraw, TipMarket.awayOrDraw},
    TipMarket.bttsYes: {TipMarket.homeScores, TipMarket.awayScores, TipMarket.over15},
    TipMarket.over25: {TipMarket.over15},
    TipMarket.under25: {TipMarket.under35},
  };
  final used = <TipMarket>{};
  final pairs = <String>{};
  bool open(TipMarket m) => !used.contains(m) && !used.contains(opposite[m]);
  final reasons = _reasons(match, details);
  Tip tip(List<({TipLeg leg, double chance})> picked, {required bool free, required Confidence level}) {
    for (final c in picked) {
      used.add(c.leg.market);
    }
    // Two selections: both chances together, a little less for the price
    // of combining them.
    final chance = picked.length == 1 ? picked.single.chance : picked.fold(1.0, (p, c) => p * c.chance) * 0.97;
    return Tip(
      matchId: match.id,
      legs: [for (final c in picked) c.leg],
      chance: chance,
      free: free,
      level: level,
      reasons: [for (final c in picked) ..._marketReason(c.leg.market, c.chance, home, away), ...reasons],
    );
  }

  /// The open single priced between [min] and [max] nearest to [target].
  Tip? single({required double min, double max = 99, required double target, required bool free, Confidence? level}) {
    final fit = candidates.where((c) => open(c.leg.market) && c.leg.odds >= min && c.leg.odds <= max).toList()
      ..sort((a, b) => (a.leg.odds - target).abs().compareTo((b.leg.odds - target).abs()));
    final c = fit.firstOrNull;
    if (c == null) return null;
    return tip([c], free: free, level: level ?? Confidence.of(c.chance));
  }

  /// Two selections from different markets with combined odds from [min]
  /// to [proMaxOdds]: the likeliest such pair. A leg may repeat a market
  /// another tip uses, but never goes against one.
  Tip? combo(Confidence level) {
    final min = level.minOdds;
    final legs = candidates
        .where((c) => !used.contains(opposite[c.leg.market]) && c.leg.odds >= 1.15 && c.leg.odds <= 1.75)
        .toList();
    ({TipLeg leg, double chance})? a, b;
    var best = 0.0;
    for (var i = 0; i < legs.length; i++) {
      for (var j = i + 1; j < legs.length; j++) {
        final x = legs[i], y = legs[j];
        final (mx, my) = (x.leg.market, y.leg.market);
        if (mx.group == my.group || opposite[mx] == my || pairs.contains('${mx.name}+${my.name}')) continue;
        if ((implies[mx]?.contains(my) ?? false) || (implies[my]?.contains(mx) ?? false)) continue;
        final odds = x.leg.odds * y.leg.odds;
        if (odds < min || odds > proMaxOdds) continue;
        final p = x.chance * y.chance;
        if (p > best) (best, a, b) = (p, x, y);
      }
    }
    if (a == null || b == null) return null;
    pairs.add('${a.leg.market.name}+${b.leg.market.name}');
    return tip([a, b], free: false, level: level);
  }

  // The Pro tips first, so the paid levels get the best prices: Max a
  // single from 1.80 to 2.00, High a single from 1.60, and Medium a
  // two-selection bet builder from 1.60. Each falls back to the other kind
  // when the match has no market that fits. Then the free tips from what is
  // left, 1.40 to 2.00.
  final pro = [
    single(min: Confidence.max.minOdds, max: proMaxOdds, target: 1.9, free: false, level: Confidence.max) ??
        combo(Confidence.max),
    single(min: Confidence.high.minOdds, max: proMaxOdds, target: 1.75, free: false, level: Confidence.high) ??
        combo(Confidence.high),
    combo(Confidence.medium) ??
        single(min: Confidence.medium.minOdds, max: proMaxOdds, target: 1.7, free: false, level: Confidence.medium),
  ].nonNulls.where(followsOddsRules).toList();
  final daily = [
    single(min: freeMinOdds, max: freeMaxOdds, target: 1.5, free: true),
    single(min: freeMinOdds, max: freeMaxOdds, target: 1.65, free: true),
  ].nonNulls.where(followsOddsRules).toList();
  return MatchTips(daily: daily, pro: pro);
}

List<String> _marketReason(TipMarket m, double p, String home, String away) => [
      switch (m) {
        TipMarket.homeWin =>
          tr('{team} win this {pct}% of the time in our simulation.', {'team': home, 'pct': (p * 100).round()}),
        TipMarket.awayWin =>
          tr('{team} come out on top in {pct}% of simulated games.', {'team': away, 'pct': (p * 100).round()}),
        TipMarket.draw => tr('An even game: the sides are close on the prices.'),
        TipMarket.homeOrDraw =>
          tr('{team} avoid defeat in {pct}% of simulated games.', {'team': home, 'pct': (p * 100).round()}),
        TipMarket.awayOrDraw =>
          tr('{team} avoid defeat in {pct}% of simulated games.', {'team': away, 'pct': (p * 100).round()}),
        TipMarket.over15 || TipMarket.over25 || TipMarket.overLine => tr('Both attacks point to an open game.'),
        TipMarket.under25 || TipMarket.under35 || TipMarket.underLine =>
          tr('A tight, low-scoring game is the likeliest script.'),
        TipMarket.bttsYes => tr('Each side scores often and concedes often.'),
        TipMarket.bttsNo => tr('At least one side struggles to score.'),
        TipMarket.homeScores => tr('{team} rarely go a home game without a goal.', {'team': home}),
        TipMarket.awayScores => tr('{team} find the net in most of their games.', {'team': away}),
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
      if (info.form.isNotEmpty) tr('form {form}', {'form': info.form.split('').join(' ')}),
      if (pos != null)
        pos.points.isEmpty
            ? tr('{rank} in the table', {'rank': ordinal(pos.rank)})
            : tr('{rank} in the table on {pts} pts', {'rank': ordinal(pos.rank), 'pts': pos.points}),
    ];
    if (parts.isNotEmpty) out.add('${t.name}: ${parts.join(', ')}.');
  }
  return out;
}

/// 1st, 2nd... in English; 1.º, 2.º... in Spanish.
String ordinal(int n) {
  if (L10n.spanish) return '$n.º';
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return '$n${switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' }}';
}

/// A Pro tip the user paid for, kept as it was bought. [result] is 'won'
/// or 'refunded' once the match is over.
class UnlockedTip {
  const UnlockedTip({required this.cost, required this.at, this.result, this.tip});
  final int cost;
  final String at;
  final String? result;

  /// The tip as bought (missing for tips bought before 0.16).
  final Tip? tip;

  UnlockedTip settled(String result) => UnlockedTip(cost: cost, at: at, result: result, tip: tip);

  Map<String, dynamic> toJson() => {'cost': cost, 'at': at, 'result': ?result, 'tip': ?tip?.toJson()};

  factory UnlockedTip.fromJson(Map<String, dynamic> j) => UnlockedTip(
        cost: (j['cost'] as num?)?.toInt() ?? 0,
        at: '${j['at'] ?? ''}',
        result: j['result'] as String?,
        tip: j['tip'] is Map ? Tip.fromJson((j['tip'] as Map).cast<String, dynamic>()) : null,
      );
}
