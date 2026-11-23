import 'community.dart';
import 'pro_tips.dart';

/// Where a bought bet came from: a Pro tip, or a bet bought from a bettor in
/// Community.
enum PurchaseSource { pro, community }

/// One bet the user bought with tokens, as the bet register's Bought
/// section lists it. Bought bets have no stake, so they count apart from the
/// bankroll: only won, lost or still open.
class PurchasedBet {
  const PurchasedBet({
    required this.id,
    required this.source,
    required this.pick,
    required this.odds,
    required this.cost,
    this.matchTitle = '',
    this.leagueName = '',
    this.kickoff,
    this.seller = '',
    this.won,
  });

  final String id;
  final PurchaseSource source;
  final String pick;
  final double odds;

  /// Tokens paid for it.
  final int cost;
  final String matchTitle, leagueName;
  final DateTime? kickoff; // UTC

  /// The bettor it was bought from, for a Community bet.
  final String seller;

  /// Won (true), lost (false) or open (null).
  final bool? won;

  bool get settled => won != null;

  /// From a Pro tip the user unlocked; null for an old one bought before
  /// tips were kept.
  static PurchasedBet? fromTip(String id, UnlockedTip u) {
    final t = u.tip;
    if (t == null) return null;
    return PurchasedBet(
      id: id,
      source: PurchaseSource.pro,
      pick: t.pick,
      odds: t.odds,
      cost: u.cost,
      matchTitle: u.match?.title ?? '',
      leagueName: u.match?.leagueName ?? '',
      kickoff: u.match?.kickoff,
      won: switch (u.result) { 'won' => true, null => null, _ => false },
    );
  }

  factory PurchasedBet.fromListing(Listing l) => PurchasedBet(
        id: l.id,
        source: PurchaseSource.community,
        pick: l.bet.leg.pick,
        odds: l.bet.leg.odds,
        cost: l.price,
        matchTitle: l.bet.matchTitle,
        leagueName: l.bet.leagueName,
        kickoff: l.bet.kickoff,
        seller: l.seller.handle,
        won: l.bet.settled ? l.bet.won : null,
      );
}

/// Won, lost and open counts of some bought bets.
class PurchaseTally {
  const PurchaseTally(this.won, this.lost, this.open);
  final int won, lost, open;

  int get total => won + lost + open;

  /// Won out of settled, 0 to 1; null before the first result.
  double? get winRate => won + lost == 0 ? null : won / (won + lost);

  factory PurchaseTally.of(Iterable<PurchasedBet> bets) {
    var w = 0, l = 0, o = 0;
    for (final b in bets) {
      switch (b.won) {
        case true:
          w++;
        case false:
          l++;
        case null:
          o++;
      }
    }
    return PurchaseTally(w, l, o);
  }
}

/// Every bet the user bought from [source], newest match first.
List<PurchasedBet> purchasedBets(
  PurchaseSource source, {
  required Map<String, UnlockedTip> tips,
  required Map<String, Listing> listings,
}) {
  final out = switch (source) {
    PurchaseSource.pro => [
        for (final e in tips.entries) ?PurchasedBet.fromTip(e.key, e.value),
      ],
    PurchaseSource.community => [for (final l in listings.values) if (!l.mine) PurchasedBet.fromListing(l)],
  };
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return out..sort((a, b) => (b.kickoff ?? epoch).compareTo(a.kickoff ?? epoch));
}
