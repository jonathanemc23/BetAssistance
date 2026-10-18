import 'fixtures.dart';

/// One reading of a match's 1X2 prices, saved each time the app loads the
/// match so the money movement tool can show how the market moved.
class OddsSnapshot {
  const OddsSnapshot({required this.at, this.provider = '', this.home, this.draw, this.away});
  final DateTime at;
  final String provider;
  final double? home, draw, away;

  static OddsSnapshot of(MatchOdds o, DateTime at) =>
      OddsSnapshot(at: at, provider: o.provider, home: o.home, draw: o.draw, away: o.away);

  bool samePrices(OddsSnapshot o) => home == o.home && draw == o.draw && away == o.away;

  Map<String, Object?> toRow() => {
    'at': at.toUtc().toIso8601String(),
    'provider': provider,
    'home': home,
    'draw': draw,
    'away': away,
  };

  static OddsSnapshot fromRow(Map<String, Object?> r) => OddsSnapshot(
    at: DateTime.parse(r['at'] as String),
    provider: (r['provider'] as String?) ?? '',
    home: (r['home'] as num?)?.toDouble(),
    draw: (r['draw'] as num?)?.toDouble(),
    away: (r['away'] as num?)?.toDouble(),
  );
}

/// How one outcome's price moved between two readings. Bookmakers don't
/// publish how many people bet or how much, but they shorten a price when
/// money comes in on it, so the change in implied chance is the visible trace
/// of where the money went.
class OutcomeMove {
  const OutcomeMove(this.label, this.from, this.to, this.chanceFrom, this.chanceTo);
  final String label;
  final double from, to;

  /// Implied chance with the bookmaker margin taken out, 0..1.
  final double chanceFrom, chanceTo;

  /// Percentage points gained (positive = the market moved towards it).
  double get shift => (chanceTo - chanceFrom) * 100;
}

class MarketMove {
  const MarketMove({required this.outcomes, required this.since, required this.provider, required this.fromOpening});
  final List<OutcomeMove> outcomes;

  /// When the first price was taken, null for a bookmaker's opening line.
  final DateTime? since;
  final String provider;
  final bool fromOpening;

  /// The outcome the market moved towards most, when the move is clear
  /// (at least one percentage point).
  OutcomeMove? get backed {
    final best = [...outcomes]..sort((a, b) => b.shift.compareTo(a.shift));
    return best.isEmpty || best.first.shift < 1 ? null : best.first;
  }

  bool get flat => outcomes.every((o) => o.shift.abs() < 1);
}

/// Margin-free implied chances of a full 1X2 (or two-way) price set.
List<double>? fairChances(List<double?> prices) {
  if (prices.any((p) => p == null || p <= 1)) return null;
  final raw = [for (final p in prices) 1 / p!];
  final sum = raw.fold<double>(0, (a, b) => a + b);
  return [for (final r in raw) r / sum];
}

MarketMove? _move(
  Match m,
  List<double?> from,
  List<double?> to, {
  required String provider,
  required bool fromOpening,
  DateTime? since,
}) {
  final labels = [m.home.name, 'Draw', m.away.name];
  final keep = [for (var i = 0; i < 3; i++) from[i] != null && to[i] != null];
  // A two-way market (no draw price) still works.
  final idx = [
    for (var i = 0; i < 3; i++)
      if (keep[i]) i,
  ];
  if (idx.length < 2) return null;
  final a = fairChances([for (final i in idx) from[i]]), b = fairChances([for (final i in idx) to[i]]);
  if (a == null || b == null) return null;
  return MarketMove(
    provider: provider,
    fromOpening: fromOpening,
    since: since,
    outcomes: [for (final (k, i) in idx.indexed) OutcomeMove(labels[i], from[i]!, to[i]!, a[k], b[k])],
  );
}

/// Price movement for [m]: from each bookmaker's opening line where the feed
/// has one, otherwise from the first price this phone saw ([history]).
MarketMove? marketMove(Match m, List<MatchOdds> odds, List<OddsSnapshot> history) {
  for (final o in odds) {
    final open = o.opening;
    if (open == null) continue;
    final mv = _move(
      m,
      [open.home, open.draw, open.away],
      [o.home, o.draw, o.away],
      provider: o.provider,
      fromOpening: true,
    );
    if (mv != null) return mv;
  }
  if (history.length < 2) return null;
  final first = history.first, last = history.last;
  return _move(
    m,
    [first.home, first.draw, first.away],
    [last.home, last.draw, last.away],
    provider: last.provider,
    fromOpening: false,
    since: first.at,
  );
}

/// The price set worth saving for [m]: the provider with the most outcomes.
MatchOdds? trackedOdds(List<MatchOdds> odds) {
  MatchOdds? best;
  for (final o in odds) {
    if (o.count >= 2 && (best == null || o.count > best.count)) best = o;
  }
  return best;
}
