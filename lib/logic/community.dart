import '../data/fixtures.dart';
import '../l10n/l10n.dart';
import 'pro_tips.dart';

// The community runs on this phone for now: profiles, the bets for sale and
// their sellers are simulated until there is a server to share them.

/// The time the challenge goes by; tests set a fixed one.
DateTime Function() communityClock = DateTime.now;

/// The user's social profile, needed to enter the community.
class SocialProfile {
  const SocialProfile({required this.name, required this.handle, this.bio = '', this.avatar = '', required this.joined});
  final String name;

  /// "@laura_bets", without the @.
  final String handle;
  final String bio;

  /// As the profile picture stores it: 'person:3', a photo path, or empty.
  final String avatar;
  final String joined;

  SocialProfile copyWith({String? name, String? handle, String? bio, String? avatar}) => SocialProfile(
        name: name ?? this.name,
        handle: handle ?? this.handle,
        bio: bio ?? this.bio,
        avatar: avatar ?? this.avatar,
        joined: joined,
      );

  Map<String, Object?> toJson() => {'name': name, 'handle': handle, 'bio': bio, 'avatar': avatar, 'joined': joined};

  static SocialProfile? fromJson(Object? j) {
    if (j is! Map || j['handle'] == null) return null;
    return SocialProfile(
      name: '${j['name'] ?? ''}',
      handle: '${j['handle']}',
      bio: '${j['bio'] ?? ''}',
      avatar: '${j['avatar'] ?? ''}',
      joined: '${j['joined'] ?? ''}',
    );
  }
}

/// A handle as the community keeps it: lower case letters, digits and
/// underscores, 3 to 20 of them. Null when [raw] can't be one.
String? cleanHandle(String raw) {
  final h = raw.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
  return RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(h) ? h : null;
}

/// One bet of the pro bettor challenge, or one bet for sale: a selection on
/// a match, settled from the final score.
class CommunityBet {
  const CommunityBet({
    required this.id,
    required this.matchId,
    required this.leagueSlug,
    required this.leagueName,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.leg,
    required this.placed,
    this.homeLogo,
    this.awayLogo,
    this.result,
  });

  final String id, matchId, leagueSlug, leagueName, home, away, placed;
  final String? homeLogo, awayLogo;
  final DateTime kickoff; // UTC
  final TipLeg leg;

  /// 'won', 'lost', or null until the match is over.
  final String? result;

  factory CommunityBet.on(Match m, TipLeg leg, {required String placed}) => CommunityBet(
        id: '${m.id}:${leg.market.name}:$placed',
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        homeLogo: m.home.logo,
        awayLogo: m.away.logo,
        kickoff: m.kickoff,
        leg: leg,
        placed: placed,
      );

  bool get settled => result != null;
  bool get won => result == 'won';
  String get matchTitle => '$home vs $away';
  League get league => leagueBySlug(leagueSlug) ?? League(leagueSlug, leagueName);

  Match toMatch() => Match(
        id: matchId,
        league: league,
        kickoff: kickoff,
        home: Team(home, home, homeLogo, null),
        away: Team(away, away, awayLogo, null),
        state: MatchState.scheduled,
        detail: '',
      );

  CommunityBet settle(int h, int a) => CommunityBet(
        id: id,
        matchId: matchId,
        leagueSlug: leagueSlug,
        leagueName: leagueName,
        home: home,
        away: away,
        homeLogo: homeLogo,
        awayLogo: awayLogo,
        kickoff: kickoff,
        leg: leg,
        placed: placed,
        result: leg.market.wins(h, a, line: leg.line) ? 'won' : 'lost',
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'match': matchId,
        'league': leagueSlug,
        'leagueName': leagueName,
        'home': home,
        'away': away,
        'homeLogo': homeLogo,
        'awayLogo': awayLogo,
        'kickoff': kickoff.toUtc().toIso8601String(),
        'leg': leg.toJson(),
        'placed': placed,
        'result': result,
      };

  static CommunityBet? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final leg = TipLeg.fromJson((j['leg'] as Map).cast<String, dynamic>());
      if (leg == null) return null;
      return CommunityBet(
        id: j['id'] as String,
        matchId: j['match'] as String,
        leagueSlug: j['league'] as String,
        leagueName: j['leagueName'] as String? ?? '',
        home: j['home'] as String,
        away: j['away'] as String,
        homeLogo: j['homeLogo'] as String?,
        awayLogo: j['awayLogo'] as String?,
        kickoff: DateTime.parse(j['kickoff'] as String).toUtc(),
        leg: leg,
        placed: j['placed'] as String,
        result: j['result'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where the user stands in the pro bettor challenge.
enum ChallengeStatus {
  /// Never accepted, or ready to start again after a wait.
  notStarted,

  /// Accepted: placing bets toward the 30.
  active,

  /// 30 bets placed, some still to be settled.
  awaitingResults,

  /// Ended under 60%, or restarted: a week before it can start again.
  waiting,

  /// 30 bets at 60% or more: the user can sell bets.
  passed,
}

/// The pro bettor challenge: 30 bets that can't be removed or changed, won
/// at 60% or more. Under 60% after 30, or a restart after 10 or more, means
/// a week's wait before starting again.
class ProChallenge {
  const ProChallenge({this.started, this.bets = const [], this.waitUntil, this.passedAt, this.attempts = 0, this.lastRate});

  static const target = 30, restartAfter = 10;
  static const passRate = 0.6;
  static const wait = Duration(days: 7);

  /// Challenge bets need odds over this, so the 30 bets can't be
  /// near-certain favourites.
  static const minOdds = 1.6;

  final DateTime? started;
  final List<CommunityBet> bets;
  final DateTime? waitUntil;
  final DateTime? passedAt;

  /// How many times the challenge was started.
  final int attempts;

  /// The win rate the last attempt ended on, when it ended under 60%.
  final double? lastRate;

  int get placed => bets.length;
  int get wins => bets.where((b) => b.won).length;
  int get settled => bets.where((b) => b.settled).length;

  /// Won out of settled, 0 to 1; null before the first result.
  double? get winRate => settled == 0 ? null : wins / settled;

  ChallengeStatus status(DateTime now) {
    if (passedAt != null) return ChallengeStatus.passed;
    if (waitUntil != null && now.isBefore(waitUntil!)) return ChallengeStatus.waiting;
    if (started == null || waitUntil != null) return ChallengeStatus.notStarted;
    if (placed >= target) return ChallengeStatus.awaitingResults;
    return ChallengeStatus.active;
  }

  bool canRestart(DateTime now) => status(now) == ChallengeStatus.active && placed >= restartAfter;

  /// Starts the challenge, from 0 bets.
  ProChallenge accept(DateTime now) => ProChallenge(started: now, attempts: attempts + 1, lastRate: lastRate);

  /// Ends this attempt: a week's wait, then it can start again.
  ProChallenge restart(DateTime now) =>
      ProChallenge(waitUntil: now.add(wait), attempts: attempts, lastRate: winRate);

  /// Why [bet] can't be placed now, or null when it can.
  String? refuse(CommunityBet bet, DateTime now) {
    if (status(now) != ChallengeStatus.active) return tr("The challenge isn't open for bets right now.");
    if (!bet.kickoff.isAfter(now)) return tr("This match has started: pick one that hasn't.");
    if (bet.leg.odds <= minOdds) return tr('Challenge bets need odds over 1.60.');
    if (bets.any((b) => b.matchId == bet.matchId && b.leg.market == bet.leg.market)) {
      return tr('You already have this bet in the challenge.');
    }
    return null;
  }

  ProChallenge place(CommunityBet bet) => _with(bets: [...bets, bet]);

  /// Settles the bets on [matchId] with the final score, then ends the
  /// attempt once all 30 are settled.
  ProChallenge settle(String matchId, int h, int a, DateTime now) {
    final next = [for (final b in bets) b.matchId == matchId && !b.settled ? b.settle(h, a) : b];
    return _with(bets: next).evaluate(now);
  }

  /// Passed at 60% or more once 30 bets are settled; else a week's wait.
  ProChallenge evaluate(DateTime now) {
    if (passedAt != null || placed < target || settled < target) return this;
    final rate = wins / settled;
    if (rate >= passRate) return _with(passedAt: now);
    return ProChallenge(waitUntil: now.add(wait), attempts: attempts, lastRate: rate);
  }

  ProChallenge _with({List<CommunityBet>? bets, DateTime? passedAt}) => ProChallenge(
        started: started,
        bets: bets ?? this.bets,
        waitUntil: waitUntil,
        passedAt: passedAt ?? this.passedAt,
        attempts: attempts,
        lastRate: lastRate,
      );

  Map<String, Object?> toJson() => {
        'started': started?.toIso8601String(),
        'bets': [for (final b in bets) b.toJson()],
        'waitUntil': waitUntil?.toIso8601String(),
        'passedAt': passedAt?.toIso8601String(),
        'attempts': attempts,
        'lastRate': lastRate,
      };

  static ProChallenge fromJson(Object? j) {
    if (j is! Map) return const ProChallenge();
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return ProChallenge(
      started: date(j['started']),
      bets: [for (final b in (j['bets'] as List? ?? const [])) ?CommunityBet.fromJson(b)],
      waitUntil: date(j['waitUntil']),
      passedAt: date(j['passedAt']),
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      lastRate: (j['lastRate'] as num?)?.toDouble(),
    );
  }
}

/// A bettor in the community: a pro who sells bets, or anyone who posts
/// free bets to gain followers.
class ProSeller {
  const ProSeller(this.handle, this.name, this.avatar, this.wins, this.losses, {this.followers = 0, this.pro = true});
  final String handle, name, avatar;
  final int wins, losses;
  final int followers;

  /// Passed the pro bettor challenge, so can sell bets.
  final bool pro;

  int get bets => wins + losses;
  int get winPercent => bets == 0 ? 0 : (wins * 100 / bets).round();
}

/// The sellers the market shows until real profiles can be shared.
const demoSellers = [
  ProSeller('goalmachine', 'Diego R.', 'person:0', 41, 22),
  ProSeller('cornerqueen', 'Sofia M.', 'person:1', 37, 19),
  ProSeller('valuehunter', 'Marcus T.', 'person:4', 52, 31),
  ProSeller('la_pizarra', 'Camila V.', 'person:7', 33, 18),
  ProSeller('underdog_fc', 'Andrés P.', 'person:2', 45, 28),
  ProSeller('stats_nerd', 'Hannah K.', 'person:9', 39, 24),
];

/// The bettors who post free bets: some pros, some still building a following.
const demoTipsters = [
  ProSeller('cornerqueen', 'Sofia M.', 'person:1', 37, 19, followers: 1840),
  ProSeller('btts_daily', 'Lucas F.', 'person:5', 21, 15, followers: 312, pro: false),
  ProSeller('la_pizarra', 'Camila V.', 'person:7', 33, 18, followers: 960),
  ProSeller('over_kings', 'Valentina G.', 'person:10', 14, 9, followers: 145, pro: false),
  ProSeller('goalmachine', 'Diego R.', 'person:0', 41, 22, followers: 2210),
  ProSeller('tikitaka_tips', 'Mateo L.', 'person:3', 9, 7, followers: 58, pro: false),
];

/// A bet for sale: who sells it, its price in tokens, and the bet itself,
/// hidden until bought. A price of 0 is a free bet, open to everyone.
class Listing {
  const Listing({required this.seller, required this.bet, required this.price, this.mine = false, this.buyers = 0});
  final ProSeller seller;
  final CommunityBet bet;
  final int price;

  /// How many bettors bought it: the hottest bets sell the most.
  final int buyers;

  bool get free => price == 0;

  /// One of the user's own bets for sale.
  final bool mine;

  String get id => bet.id;

  Map<String, Object?> toJson() => {
        'seller': seller.handle,
        'sellerName': seller.name,
        'sellerAvatar': seller.avatar,
        'wins': seller.wins,
        'losses': seller.losses,
        'followers': seller.followers,
        'pro': seller.pro,
        'bet': bet.toJson(),
        'price': price,
        'mine': mine,
        'buyers': buyers,
      };

  Listing settle(int h, int a) =>
      Listing(seller: seller, bet: bet.settle(h, a), price: price, mine: mine, buyers: buyers);

  static Listing? fromJson(Object? j) {
    if (j is! Map) return null;
    final bet = CommunityBet.fromJson(j['bet']);
    if (bet == null) return null;
    return Listing(
      seller: ProSeller('${j['seller'] ?? ''}', '${j['sellerName'] ?? ''}', '${j['sellerAvatar'] ?? ''}',
          (j['wins'] as num?)?.toInt() ?? 0, (j['losses'] as num?)?.toInt() ?? 0,
          followers: (j['followers'] as num?)?.toInt() ?? 0, pro: j['pro'] != false),
      bet: bet,
      price: (j['price'] as num?)?.toInt() ?? 1,
      mine: j['mine'] == true,
      buyers: (j['buyers'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The token price of a bet for sale, by its odds: longer odds cost more.
int listingPrice(double odds) => odds >= 2.2 ? 3 : (odds >= 1.8 ? 2 : 1);

/// The day's simulated bets for sale: one per match still to start and seller, a market
/// priced between 1.50 and 2.60, the same on every visit.
List<Listing> demoListings(List<Match> matches, {required String day}) {
  final out = <Listing>[];
  for (final (i, m) in matches.indexed) {
    if (m.state != MatchState.scheduled) continue;
    final markets = [
      for (final c in pricedMarkets(m, const MatchDetails()))
        if (c.leg.odds >= 1.5 && c.leg.odds <= 2.6) c.leg,
    ];
    if (markets.isEmpty) continue;
    final seed = m.id.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x3fffffff);
    final leg = markets[seed % markets.length];
    final seller = demoSellers[(seed + i) % demoSellers.length];
    out.add(Listing(
      seller: seller,
      bet: CommunityBet.on(m, leg, placed: '${seller.handle}:$day'),
      price: listingPrice(leg.odds),
      buyers: 8 + (seed ~/ 7) % 40 + seller.winPercent ~/ 4,
    ));
  }
  return out;
}

/// The [n] bets for sale that sold the most.
List<Listing> hottest(Iterable<Listing> listings, {int n = 3}) =>
    ([...listings.where((l) => !l.mine)]..sort((a, b) => b.buyers.compareTo(a.buyers))).take(n).toList();

/// The day's simulated free bets: one per match still to start, from a
/// tipster other than its seller, so they don't repeat the bets for sale.
List<Listing> demoFreeBets(List<Match> matches, {required String day}) {
  final out = <Listing>[];
  for (final (i, m) in matches.indexed) {
    if (m.state != MatchState.scheduled) continue;
    final markets = [
      for (final c in pricedMarkets(m, const MatchDetails()))
        if (c.leg.odds >= 1.4 && c.leg.odds <= 2.4) c.leg,
    ];
    if (markets.isEmpty) continue;
    final seed = '${m.id}:free'.codeUnits.fold<int>(11, (h, c) => (h * 37 + c) & 0x3fffffff);
    final leg = markets[seed % markets.length];
    final tipster = demoTipsters[(seed + i) % demoTipsters.length];
    out.add(Listing(seller: tipster, bet: CommunityBet.on(m, leg, placed: 'free:${tipster.handle}:$day'), price: 0));
  }
  return out;
}

/// Why the user can't post [bet] as a free bet, or null when they can.
String? refuseFreeBet(List<Listing> mine, CommunityBet bet, DateTime now) {
  if (!bet.kickoff.isAfter(now)) return tr("This match has started: pick one that hasn't.");
  if (mine.any((l) => l.bet.matchId == bet.matchId && l.bet.leg.market == bet.leg.market)) {
    return tr('You already posted this bet.');
  }
  final local = now.toLocal();
  final dayStart = DateTime(local.year, local.month, local.day);
  final today = mine.where((l) => DateTime.tryParse(l.bet.placed)?.toLocal().isBefore(dayStart) == false);
  if (today.length >= maxFreeBetsPerDay) return tr('You can post up to 3 free bets a day.');
  return null;
}

/// Free bets a bettor can post in a day, so followers see their best picks.
const maxFreeBetsPerDay = 3;
