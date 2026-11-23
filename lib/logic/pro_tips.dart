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

  /// Lowest decimal odds a Pro tip may have: 1.80 at every level.
  double get minOdds => proMinOdds;

  /// The level for a free tip, from its chance: High from 62%, else Medium.
  static Confidence of(double chance) => chance >= 0.62 ? Confidence.high : Confidence.medium;
}

/// The odds rules: free tips from 1.40 to 2.00; Pro tips (High for 2 tokens,
/// Max for 3) from 1.80 to 2.30, always a single on a real bookmaker price.
/// A Pro tip needs at least a 40% chance; Max needs 50%.
const freeMinOdds = 1.4, freeMaxOdds = 2.0, proMinOdds = 1.8, proMaxOdds = 2.3, proMinChance = 0.40;

bool followsOddsRules(Tip t) => t.legs.length == 1 &&
    (t.free
        ? t.odds >= freeMinOdds && t.odds <= freeMaxOdds
        : t.level != Confidence.medium && t.odds >= proMinOdds && t.odds <= proMaxOdds);

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

/// A market a bet can be on, with the bookmaker's decimal price when the
/// feed has one. Without a price the user types the odds in; the app never
/// makes one up.
typedef MarketOption = ({TipMarket market, String pick, double? line, double? odds});

/// The bookmaker lines the tips are read from: the match list's own prices
/// when it has them, so the tips are the same on every page, else the first
/// provider on the match page.
MatchOdds? _tipBook(Match match, MatchDetails details) =>
    [?match.odds, ...details.odds].where((o) => o.home != null && o.away != null).firstOrNull;

/// Every market of [match] a bet can be on, each with the real price when a
/// bookmaker in the feed offers one (null otherwise). With [allBooks] every
/// provider on the match page counts; otherwise only the one the tips read.
List<MarketOption> matchMarkets(Match match, MatchDetails details, {bool allBooks = true}) {
  final soccer = match.league.knownSport == Sport.soccer;
  final tipBook = _tipBook(match, details);
  final books = allBooks ? [?tipBook, ...details.odds] : [?tipBook];
  final book = tipBook;
  double? extra(String label) =>
      [for (final b in books) for (final e in b.extras) if (e.$1 == label) e.$2].firstOrNull;
  final totals = books.where((o) => o.totalLine != null && o.over != null && o.under != null).firstOrNull;
  final home = match.home.name, away = match.away.name;
  final out = <MarketOption>[
    (market: TipMarket.homeWin, pick: '$home to win', line: null, odds: book?.home),
    (market: TipMarket.awayWin, pick: '$away to win', line: null, odds: book?.away),
  ];
  if (soccer) {
    final line25 = totals?.totalLine == 2.5;
    out.addAll([
      (market: TipMarket.draw, pick: 'Draw', line: null, odds: book?.draw),
      (market: TipMarket.homeOrDraw, pick: '$home or draw', line: null, odds: extra('Double chance 1X')),
      (market: TipMarket.awayOrDraw, pick: '$away or draw', line: null, odds: extra('Double chance X2')),
      (market: TipMarket.over15, pick: 'Over 1.5 goals', line: null, odds: null),
      (market: TipMarket.over25, pick: 'Over 2.5 goals', line: null, odds: line25 ? totals!.over : null),
      (market: TipMarket.under25, pick: 'Under 2.5 goals', line: null, odds: line25 ? totals!.under : null),
      (market: TipMarket.under35, pick: 'Under 3.5 goals', line: null, odds: null),
      if (totals != null && !line25) ...[
        (market: TipMarket.overLine, pick: 'Over ${totals.totalLine} goals', line: totals.totalLine, odds: totals.over),
        (market: TipMarket.underLine, pick: 'Under ${totals.totalLine} goals', line: totals.totalLine, odds: totals.under),
      ],
      (market: TipMarket.bttsYes, pick: 'Both teams to score', line: null, odds: null),
      (market: TipMarket.bttsNo, pick: 'Not both teams to score', line: null, odds: null),
      (market: TipMarket.homeScores, pick: '$home to score', line: null, odds: null),
      (market: TipMarket.awayScores, pick: '$away to score', line: null, odds: null),
    ]);
  } else if (totals != null) {
    final unit = match.league.knownSport.scoreUnit;
    out.addAll([
      (market: TipMarket.overLine, pick: 'Over ${totals.totalLine} $unit', line: totals.totalLine, odds: totals.over),
      (market: TipMarket.underLine, pick: 'Under ${totals.totalLine} $unit', line: totals.totalLine, odds: totals.under),
    ]);
  }
  return out;
}

/// The markets of [match] with a real bookmaker price, each with its chance:
/// what the bookmaker's prices imply once their margin is taken out. Nothing
/// is estimated: a market the feed doesn't price isn't here.
List<({TipLeg leg, double chance})> pricedMarkets(Match match, MatchDetails details) {
  final book = _tipBook(match, details);
  if (book == null) return const [];
  // Win chances from the 1X2 prices, margin removed.
  final ih = 1 / book.home!, ia = 1 / book.away!, id = book.draw == null ? 0.0 : 1 / book.draw!;
  final sum = ih + ia + id;
  final pH = ih / sum, pA = ia / sum, pD = id / sum;
  final totals = [book, ...details.odds].where((o) => o.totalLine != null && o.over != null && o.under != null).firstOrNull;
  final pOver = totals == null ? null : (1 / totals.over!) / (1 / totals.over! + 1 / totals.under!);
  double? chance(TipMarket m) => switch (m) {
        TipMarket.homeWin => pH,
        TipMarket.awayWin => pA,
        TipMarket.draw => pD > 0 ? pD : null,
        TipMarket.homeOrDraw => pD > 0 ? pH + pD : null,
        TipMarket.awayOrDraw => pD > 0 ? pA + pD : null,
        TipMarket.over25 || TipMarket.overLine => pOver,
        TipMarket.under25 || TipMarket.underLine => pOver == null ? null : 1 - pOver,
        _ => null,
      };
  return [
    for (final o in matchMarkets(match, details, allBooks: false))
      if (o.odds case final odds? when odds > 1)
        if (chance(o.market) case final p? when p > 0)
          (leg: TipLeg(o.market, o.pick, odds, line: o.line), chance: p),
  ];
}

/// Whether two markets can both win: some final score wins both.
bool _compatible(TipLeg a, TipLeg b) {
  if (a.market == b.market) return false;
  if (a.line != null || b.line != null) {
    final lines = {TipMarket.overLine, TipMarket.underLine};
    return !(lines.contains(a.market) && lines.contains(b.market));
  }
  for (var h = 0; h <= 8; h++) {
    for (var w = 0; w <= 8; w++) {
      if (a.market.wins(h, w) && b.market.wins(h, w)) return true;
    }
  }
  return false;
}

/// The day's tips for [match], from real bookmaker prices only. Pro tips:
/// singles at odds from 1.80 to 2.30 the market gives at least a 40% chance,
/// Max from 50%, at most two. Free tips: singles from 1.40 to 2.00 among the
/// other markets, High from 62% and Medium below, at most two. Tips never go
/// against each other. Only the match list's prices go in, so the tips are
/// the same on every page; [details] only adds the reasons.
MatchTips pickTips(Match match, MatchDetails details) {
  final candidates = [...pricedMarkets(match, details)]..sort((a, b) => b.chance.compareTo(a.chance));
  final reasons = _reasons(match, details);
  final provider = _tipBook(match, details)?.provider ?? '';
  final picked = <TipLeg>[];
  Tip tip(({TipLeg leg, double chance}) c, {required bool free, required Confidence level}) {
    picked.add(c.leg);
    return Tip(
      matchId: match.id,
      legs: [c.leg],
      chance: c.chance,
      free: free,
      level: level,
      reasons: [_marketReason(c.leg.market, c.chance, match.home.name, match.away.name, provider), ...reasons],
    );
  }

  bool fits(TipLeg l) => picked.every((p) => _compatible(p, l));
  final pro = <Tip>[];
  void addPro(int upTo) {
    for (final c in candidates) {
      if (pro.length >= upTo) break;
      if (picked.contains(c.leg)) continue;
      if (c.leg.odds < proMinOdds || c.leg.odds > proMaxOdds || c.chance < proMinChance || !fits(c.leg)) continue;
      pro.add(tip(c, free: false, level: c.chance >= 0.5 ? Confidence.max : Confidence.high));
    }
  }

  // The best Pro tip first, then the free ones, then a second Pro tip: a
  // long-priced second Pro pick never crowds out the free picks.
  addPro(1);
  final daily = <Tip>[];
  for (final c in candidates) {
    if (daily.length == 2) break;
    if (picked.contains(c.leg)) continue;
    if (c.leg.odds < freeMinOdds || c.leg.odds > freeMaxOdds || !fits(c.leg)) continue;
    daily.add(tip(c, free: true, level: Confidence.of(c.chance)));
  }
  addPro(2);
  return MatchTips(daily: daily, pro: pro);
}

/// Why the tip: the chance the bookmaker's prices give it.
String _marketReason(TipMarket m, double p, String home, String away, String provider) {
  final pct = (p * 100).round();
  return switch (m) {
    TipMarket.homeWin || TipMarket.awayWin => tr('The bookmaker prices {team} at a {pct}% chance to win, margin removed.',
        {'team': m == TipMarket.homeWin ? home : away, 'pct': pct}),
    TipMarket.homeOrDraw || TipMarket.awayOrDraw => tr('The bookmaker prices {team} at a {pct}% chance to avoid defeat.',
        {'team': m == TipMarket.homeOrDraw ? home : away, 'pct': pct}),
    _ => provider.isEmpty
        ? tr("The bookmaker's prices give this pick a {pct}% chance, margin removed.", {'pct': pct})
        : tr("{provider}'s prices give this pick a {pct}% chance, margin removed.", {'provider': provider, 'pct': pct}),
  };
}

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

/// The day's free picks across [tips]: the likeliest free tips, one per
/// match, [n] at most, of which at most [highs] are High and the rest
/// Medium.
List<(M, Tip)> freePicksOfTheDay<M>(Iterable<(M, Tip)> tips, {int n = 3, int highs = 2}) {
  final all = [for (final t in tips) if (t.$2.free) t]..sort((a, b) => b.$2.chance.compareTo(a.$2.chance));
  final out = <(M, Tip)>[];
  final matches = <String>{};
  var high = 0;
  for (final t in all) {
    if (out.length == n) break;
    if (matches.contains(t.$2.matchId)) continue;
    if (t.$2.level != Confidence.medium) {
      if (high == highs) continue;
      high++;
    }
    matches.add(t.$2.matchId);
    out.add(t);
  }
  return out;
}
