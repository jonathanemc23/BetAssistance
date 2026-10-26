import 'dart:convert';

import 'fixtures.dart';
import 'models.dart';

/// A parlay the user is building or tracking in the Parlay builder. Unlike a
/// [Bet] it doesn't touch the bankroll; it can be logged as a bet later.
class Parlay {
  const Parlay({
    this.id,
    required this.name,
    this.stake = 0,
    this.status = BetStatus.pending,
    this.legs = const [],
    this.check,
    required this.created,
    required this.updated,
  });

  final int? id;
  final String name;
  final double stake;
  final BetStatus status;
  final List<ParlayLeg> legs;

  /// The latest check, kept until the user runs it again.
  final ParlayCheck? check;
  final String created;
  final String updated;

  double get odds => parlayOdds([for (final l in legs) l.asBetLeg()]);
  double get potentialReturn => stake * odds;
  bool get isOpen => status == BetStatus.pending;

  Parlay copyWith({String? name, double? stake, BetStatus? status, List<ParlayLeg>? legs, ParlayCheck? check, String? updated}) =>
      Parlay(
        id: id,
        name: name ?? this.name,
        stake: stake ?? this.stake,
        status: status ?? this.status,
        legs: legs ?? this.legs,
        check: check ?? this.check,
        created: created,
        updated: updated ?? this.updated,
      );

  /// The same parlay as a bet, for the bet register and share links.
  Bet toBet({required String date, required String created}) => Bet(
        type: BetType.parlay,
        selection: '${legs.length}-leg parlay',
        sport: legs.map((l) => l.sport).toSet().length == 1 ? legs.first.sport : 'Mixed',
        date: date,
        stake: stake,
        odds: odds,
        created: created,
        legs: [for (final l in legs) l.asBetLeg().copyWith(status: BetStatus.pending)],
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name,
        'stake': stake,
        'status': status.dbValue,
        'check_json': check == null ? null : jsonEncode(check!.toJson()),
        'created': created,
        'updated': updated,
      };

  factory Parlay.fromRow(Map<String, Object?> r, List<ParlayLeg> legs) {
    ParlayCheck? check;
    final raw = r['check_json'] as String?;
    if (raw != null) {
      try {
        check = ParlayCheck.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {} // an unreadable check is simply dropped
    }
    return Parlay(
      id: r['id'] as int?,
      name: (r['name'] as String?) ?? 'Parlay',
      stake: (r['stake'] as num?)?.toDouble() ?? 0,
      status: BetStatusX.parse((r['status'] as String?) ?? 'pending'),
      legs: legs,
      check: check,
      created: (r['created'] as String?) ?? '',
      updated: (r['updated'] as String?) ?? '',
    );
  }
}

/// One selection. A leg picked from the Matches list keeps the match so the
/// check can load its data; an external leg only has the text and the price.
class ParlayLeg {
  const ParlayLeg({
    this.id,
    required this.selection,
    this.event = '',
    this.sport = 'Soccer',
    required this.odds,
    this.status = BetStatus.pending,
    this.matchId,
    this.leagueSlug,
    this.leagueName,
    this.home,
    this.away,
    this.kickoff,
  });

  final int? id;
  final String selection;
  final String event;
  final String sport;
  final double odds;
  final BetStatus status;
  final String? matchId, leagueSlug, leagueName, home, away;
  final DateTime? kickoff; // UTC

  bool get isLinked => matchId != null && leagueSlug != null && home != null && away != null;

  factory ParlayLeg.fromMatch(Match m, String selection, double odds) => ParlayLeg(
        selection: selection,
        event: m.title,
        sport: m.league.knownSport.label,
        odds: odds,
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        kickoff: m.kickoff,
      );

  /// This pick tied to the real match [m], as if chosen from the Matches list.
  ParlayLeg linkedTo(Match m, {String? selection}) => ParlayLeg(
        id: id,
        selection: selection ?? this.selection,
        event: m.title,
        sport: sport,
        odds: odds,
        status: status,
        matchId: m.id,
        leagueSlug: m.league.slug,
        leagueName: m.league.name,
        home: m.home.name,
        away: m.away.name,
        kickoff: m.kickoff,
      );

  /// Enough of a [Match] to fetch its details.
  Match? toMatch() => !isLinked
      ? null
      : Match(
          id: matchId!,
          league: League(leagueSlug!, leagueName ?? ''),
          kickoff: kickoff ?? DateTime.now().toUtc(),
          home: Team(home!, home!, null, null),
          away: Team(away!, away!, null, null),
          state: MatchState.other,
          detail: '',
        );

  BetLeg asBetLeg() => BetLeg(
        selection: selection,
        event: event,
        sport: sport,
        odds: odds,
        status: status,
        matchId: isLinked ? matchId : null,
        leagueSlug: isLinked ? leagueSlug : null,
        leagueName: isLinked ? leagueName : null,
        kickoff: isLinked ? kickoff : null,
      );

  ParlayLeg copyWith({BetStatus? status}) => ParlayLeg(
        id: id, selection: selection, event: event, sport: sport, odds: odds, status: status ?? this.status,
        matchId: matchId, leagueSlug: leagueSlug, leagueName: leagueName, home: home, away: away, kickoff: kickoff,
      );

  Map<String, Object?> toRow(int parlayId, int position) => {
        'parlay_id': parlayId,
        'position': position,
        'selection': selection,
        'event': event,
        'sport': sport,
        'odds': odds,
        'status': status.dbValue,
        'match_id': matchId,
        'league_slug': leagueSlug,
        'league_name': leagueName,
        'home': home,
        'away': away,
        'kickoff': kickoff?.toUtc().toIso8601String(),
      };

  factory ParlayLeg.fromRow(Map<String, Object?> r) => ParlayLeg(
        id: r['id'] as int?,
        selection: (r['selection'] as String?) ?? '',
        event: (r['event'] as String?) ?? '',
        sport: (r['sport'] as String?) ?? 'Other',
        odds: (r['odds'] as num).toDouble(),
        status: BetStatusX.parse((r['status'] as String?) ?? 'pending'),
        matchId: r['match_id'] as String?,
        leagueSlug: r['league_slug'] as String?,
        leagueName: r['league_name'] as String?,
        home: r['home'] as String?,
        away: r['away'] as String?,
        kickoff: DateTime.tryParse((r['kickoff'] as String?) ?? '')?.toUtc(),
      );
}

/// Result of checking a parlay: an overall view and one verdict per leg.
class ParlayCheck {
  const ParlayCheck({
    required this.checked,
    required this.risk,
    required this.summary,
    required this.legs,
    this.source = 'Match data',
  });

  final String checked; // ISO timestamp
  final String risk; // Low, Medium or High
  final List<String> summary;
  final List<LegCheck> legs;

  /// Who produced it, e.g. "Match data" now or an AI model later.
  final String source;

  Map<String, Object?> toJson() => {
        'checked': checked,
        'risk': risk,
        'summary': summary,
        'legs': [for (final l in legs) l.toJson()],
        'source': source,
      };

  factory ParlayCheck.fromJson(Map<String, dynamic> j) => ParlayCheck(
        checked: j['checked'] as String? ?? '',
        risk: j['risk'] as String? ?? '',
        summary: [for (final s in (j['summary'] as List? ?? const [])) '$s'],
        legs: [for (final l in (j['legs'] as List? ?? const [])) LegCheck.fromJson(l as Map<String, dynamic>)],
        source: j['source'] as String? ?? 'Match data',
      );
}

/// How one leg looks: [verdict] is a short label ("Good price", "Fair price",
/// "Below market", "Price only"), [tone] says how to colour it.
class LegCheck {
  const LegCheck({required this.selection, required this.verdict, required this.tone, required this.lines});
  final String selection;
  final String verdict;
  final LegTone tone;
  final List<String> lines;

  Map<String, Object?> toJson() => {'selection': selection, 'verdict': verdict, 'tone': tone.name, 'lines': lines};

  factory LegCheck.fromJson(Map<String, dynamic> j) => LegCheck(
        selection: j['selection'] as String? ?? '',
        verdict: j['verdict'] as String? ?? '',
        tone: LegTone.values.firstWhere((t) => t.name == j['tone'], orElse: () => LegTone.neutral),
        lines: [for (final s in (j['lines'] as List? ?? const [])) '$s'],
      );
}

enum LegTone { good, neutral, warning }
