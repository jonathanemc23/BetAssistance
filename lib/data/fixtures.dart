import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/markets.dart';
import 'match_details.dart';
import 'models.dart';
import 'request_gate.dart';

export 'match_details.dart';

/// Sports the Matches tab lists. [espn] is the sport in ESPN's feed paths,
/// [label] the sport as bets name it (see `sports`).
enum Sport {
  soccer('soccer', 'Soccer', 'Football', '⚽'),
  basketball('basketball', 'Basketball', 'Basketball', '🏀'),
  baseball('baseball', 'Baseball', 'Baseball', '⚾');

  const Sport(this.espn, this.label, this.title, this.emoji);
  final String espn;
  final String label;
  final String title;
  final String emoji;

  /// What the totals line counts in this sport: "Over 2.5 goals".
  String get scoreUnit => switch (this) {
    Sport.soccer => 'goals',
    Sport.basketball => 'points',
    Sport.baseball => 'runs',
  };

  static Sport byName(String? name) => Sport.values.firstWhere((s) => s.name == name, orElse: () => Sport.soccer);
}

/// Fixtures from ESPN's public scoreboard feed (site.api.espn.com, free and
/// keyless). One request per league and day. Leagues ESPN lacks or doesn't
/// keep up to date also read TheSportsDB's free feed (thesportsdb.com), see
/// [League.tsdb].
class League {
  const League(this.slug, this.name, {this.tsdb, this.sport = Sport.soccer});
  final String slug;
  final String name;
  final Sport sport;

  /// TheSportsDB league id. Its results fill in scores ESPN never updates
  /// (Chile), and leagues with a `tsdb.` slug come only from there
  /// (Belgian Cup).
  final int? tsdb;

  bool get onEspn => !slug.startsWith('tsdb.');

  /// The sport as the app lists it: a league rebuilt from a saved slug
  /// (a parlay leg, a bet) doesn't carry it.
  Sport get knownSport => leagueBySlug(slug)?.sport ?? sport;
}

class Country {
  const Country(this.code, this.name, this.flag, this.leagues);
  final String code;
  final String name;
  final String flag;
  final List<League> leagues;

  /// This country's leagues in [sport]; every league when null.
  List<League> leaguesIn(Sport? sport) => sport == null ? leagues : [for (final l in leagues) if (l.sport == sport) l];

  bool has(Sport sport) => leagues.any((l) => l.sport == sport);
}

const _bb = Sport.basketball, _bsb = Sport.baseball;

const countries = <Country>[
  Country('int', 'International', '🌍', [
    League('uefa.champions', 'Champions League'),
    League('uefa.europa', 'Europa League'),
    League('uefa.europa.conf', 'Conference League'),
    League('conmebol.libertadores', 'Copa Libertadores'),
    League('conmebol.sudamericana', 'Copa Sudamericana'),
    League('concacaf.champions', 'CONCACAF Champions Cup'),
    League('fifa.world', 'World Cup'),
    League('fifa.friendly', 'International friendlies'),
    League('uefa.wchampions', "Women's Champions League"),
    League('fifa.wwc', "Women's World Cup"),
    League('uefa.weuro', "Women's Euro"),
    League('conmebol.america.femenina', 'Copa América Femenina'),
    League('fifa.friendly.w', "Women's friendlies"),
    League('uefa.w.europa', "Women's Europa Cup"),
    League('uefa.w.nations', "Women's Nations League"),
    League('concacaf.w.champions_cup', 'CONCACAF W Champions Cup'),
    League('tsdb.4546', 'EuroLeague', tsdb: 4546, sport: _bb),
    League('tsdb.4547', 'EuroCup', tsdb: 4547, sport: _bb),
    League('tsdb.4548', 'Basketball Champions League', tsdb: 4548, sport: _bb),
    League('tsdb.4477', 'ABA League', tsdb: 4477, sport: _bb),
    League('fiba', 'FIBA World Cup', sport: _bb),
    League('world-baseball-classic', 'World Baseball Classic', sport: _bsb),
    League('caribbean-series', 'Caribbean Series', sport: _bsb),
  ]),
  Country('arg', 'Argentina', '🇦🇷', [
    League('arg.1', 'Liga Profesional'),
    League('arg.2', 'Primera Nacional'),
    League('arg.copa', 'Copa Argentina'),
    League('tsdb.4734', 'Liga Nacional', tsdb: 4734, sport: _bb),
  ]),
  Country('aus', 'Australia', '🇦🇺', [
    League('aus.1', 'A-League'),
    League('aus.w.1', 'A-League Women'),
    League('nbl', 'NBL', sport: _bb),
    League('tsdb.5113', 'WNBL', tsdb: 5113, sport: _bb),
    League('tsdb.5107', 'Australian Baseball League', tsdb: 5107, sport: _bsb),
  ]),
  Country('aut', 'Austria', '🇦🇹', [League('aut.1', 'Bundesliga')]),
  Country('bel', 'Belgium', '🇧🇪', [
    League('bel.1', 'Pro League'),
    League('tsdb.5831', 'Belgian Cup', tsdb: 5831),
    League('tsdb.5942', "Women's Super League", tsdb: 5942),
  ]),
  Country('bol', 'Bolivia', '🇧🇴', [League('bol.1', 'División Profesional')]),
  Country('bra', 'Brazil', '🇧🇷', [
    League('bra.1', 'Série A'),
    League('bra.2', 'Série B'),
    League('tsdb.4625', 'Série C', tsdb: 4625),
    League('bra.copa_do_brazil', 'Copa do Brasil'),
    League('tsdb.5201', 'Brasileirão Feminino', tsdb: 5201),
  ]),
  // Leagues ESPN doesn't carry, or stopped updating (Serie C, Cyprus,
  // Ecuador's Serie B, 3. Liga, Ireland, Romania, Switzerland), come from
  // TheSportsDB (`tsdb.` slugs).
  Country('bul', 'Bulgaria', '🇧🇬', [League('tsdb.4626', 'First League', tsdb: 4626)]),
  Country('chi', 'Chile', '🇨🇱', [
    League('chi.1', 'Primera División', tsdb: 4627),
    League('chi.copa_chi', 'Copa Chile', tsdb: 5378),
  ]),
  Country('can', 'Canada', '🇨🇦', [League('can.w.nsl', 'Northern Super League (women)')]),
  Country('chn', 'China', '🇨🇳', [League('chn.1', 'Super League'), League('tsdb.4442', 'CBA', tsdb: 4442, sport: _bb)]),
  // ESPN's Primera B feed (col.2) has had no fixtures since 2025, so it
  // comes from TheSportsDB.
  Country('col', 'Colombia', '🇨🇴', [
    League('col.1', 'Primera A'),
    League('tsdb.4951', 'Primera B', tsdb: 4951),
    League('col.copa', 'Copa Colombia'),
  ]),
  Country('crc', 'Costa Rica', '🇨🇷', [League('crc.1', 'Primera División')]),
  Country('cro', 'Croatia', '🇭🇷', [
    League('tsdb.4629', 'HNL', tsdb: 4629),
    League('tsdb.5910', 'Prva NL', tsdb: 5910),
  ]),
  Country('cub', 'Cuba', '🇨🇺', [League('tsdb.5108', 'Serie Nacional', tsdb: 5108, sport: _bsb)]),
  Country('cyp', 'Cyprus', '🇨🇾', [League('tsdb.4630', 'First Division', tsdb: 4630)]),
  Country('den', 'Denmark', '🇩🇰', [League('den.1', 'Superliga'), League('tsdb.5202', 'Kvindeliga', tsdb: 5202)]),
  Country('ecu', 'Ecuador', '🇪🇨', [League('ecu.1', 'LigaPro'), League('tsdb.4957', 'Serie B', tsdb: 4957)]),
  Country('egy', 'Egypt', '🇪🇬', [League('tsdb.4829', 'Premier League', tsdb: 4829)]),
  Country('eng', 'England', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', [
    League('eng.1', 'Premier League'),
    League('eng.2', 'Championship'),
    League('eng.3', 'League One'),
    League('eng.4', 'League Two'),
    League('eng.5', 'National League'),
    League('eng.fa', 'FA Cup'),
    League('eng.league_cup', 'EFL Cup'),
    League('eng.w.1', "Women's Super League"),
    League('eng.w.fa', "Women's FA Cup"),
  ]),
  Country('fra', 'France', '🇫🇷', [
    League('fra.1', 'Ligue 1'),
    League('fra.2', 'Ligue 2'),
    League('fra.coupe_de_france', 'Coupe de France'),
    League('fra.w.1', 'Première Ligue (women)'),
    League('tsdb.4423', 'LNB Élite', tsdb: 4423, sport: _bb),
  ]),
  Country('ger', 'Germany', '🇩🇪', [
    League('ger.1', 'Bundesliga'),
    League('ger.2', '2. Bundesliga'),
    League('tsdb.4639', '3. Liga', tsdb: 4639),
    League('ger.dfb_pokal', 'DFB-Pokal'),
    League('tsdb.5204', 'Frauen-Bundesliga', tsdb: 5204),
    League('tsdb.4441', 'BBL', tsdb: 4441, sport: _bb),
  ]),
  Country('gre', 'Greece', '🇬🇷', [
    League('gre.1', 'Super League'),
    League('tsdb.4452', 'Basket League', tsdb: 4452, sport: _bb),
  ]),
  Country('gua', 'Guatemala', '🇬🇹', [League('gua.1', 'Liga Nacional')]),
  Country('hon', 'Honduras', '🇭🇳', [League('hon.1', 'Liga Nacional')]),
  Country('hun', 'Hungary', '🇭🇺', [League('tsdb.4690', 'NB I', tsdb: 4690)]),
  Country('irn', 'Iran', '🇮🇷', [League('tsdb.4742', 'Persian Gulf Pro League', tsdb: 4742)]),
  Country('irl', 'Ireland', '🇮🇪', [League('tsdb.4643', 'Premier Division', tsdb: 4643)]),
  Country('isr', 'Israel', '🇮🇱', [League('tsdb.4474', 'Basketball Premier League', tsdb: 4474, sport: _bb)]),
  Country('ita', 'Italy', '🇮🇹', [
    League('ita.1', 'Serie A'),
    League('ita.2', 'Serie B'),
    League('ita.coppa_italia', 'Coppa Italia'),
    League('tsdb.5205', 'Serie A Women', tsdb: 5205),
    League('tsdb.4433', 'Lega Basket Serie A', tsdb: 4433, sport: _bb),
  ]),
  Country('jpn', 'Japan', '🇯🇵', [
    League('jpn.1', 'J1 League'),
    League('tsdb.4977', 'B.League B1', tsdb: 4977, sport: _bb),
    League('tsdb.4591', 'NPB', tsdb: 4591, sport: _bsb),
  ]),
  Country('ltu', 'Lithuania', '🇱🇹', [
    League('tsdb.4651', 'TOPLYGA', tsdb: 4651),
    League('tsdb.4478', 'LKL', tsdb: 4478, sport: _bb),
  ]),
  Country('mex', 'Mexico', '🇲🇽', [
    League('mex.1', 'Liga MX'),
    League('mex.2', 'Liga de Expansión'),
    League('tsdb.5206', 'Liga MX Femenil', tsdb: 5206),
    League('tsdb.5119', 'LNBP', tsdb: 5119, sport: _bb),
    League('tsdb.5064', 'Liga Mexicana de Béisbol', tsdb: 5064, sport: _bsb),
    League('tsdb.5109', 'Liga Mexicana del Pacífico', tsdb: 5109, sport: _bsb),
  ]),
  Country('ned', 'Netherlands', '🇳🇱', [
    League('ned.1', 'Eredivisie'),
    League('ned.2', 'Eerste Divisie'),
    League('ned.cup', 'KNVB Cup'),
    League('ned.w.1', 'Vrouwen Eredivisie'),
  ]),
  Country('nor', 'Norway', '🇳🇴', [League('nor.1', 'Eliteserien'), League('tsdb.5208', 'Toppserien', tsdb: 5208)]),
  Country('par', 'Paraguay', '🇵🇾', [League('par.1', 'Primera División')]),
  Country('per', 'Peru', '🇵🇪', [League('per.1', 'Liga 1')]),
  Country('pol', 'Poland', '🇵🇱', [League('tsdb.4422', 'Ekstraklasa', tsdb: 4422)]),
  Country('por', 'Portugal', '🇵🇹', [
    League('por.1', 'Primeira Liga'),
    League('por.taca.portugal', 'Taça de Portugal'),
    League('tsdb.5404', 'Campeonato Nacional Feminino', tsdb: 5404),
  ]),
  Country('pur', 'Puerto Rico', '🇵🇷', [League('tsdb.5832', 'LBPRC', tsdb: 5832, sport: _bsb)]),
  Country('rou', 'Romania', '🇷🇴', [League('tsdb.4691', 'Liga I', tsdb: 4691), League('tsdb.5946', 'Liga I Feminin', tsdb: 5946)]),
  Country('ksa', 'Saudi Arabia', '🇸🇦', [League('ksa.1', 'Pro League')]),
  Country('sco', 'Scotland', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', [League('sco.1', 'Premiership'), League('sco.2', 'Championship')]),
  Country('srb', 'Serbia', '🇷🇸', [
    League('tsdb.4671', 'SuperLiga', tsdb: 4671),
    League('tsdb.5121', 'KLS', tsdb: 5121, sport: _bb),
  ]),
  Country('svk', 'Slovakia', '🇸🇰', [League('tsdb.4672', 'Niké Liga', tsdb: 4672)]),
  Country('kor', 'South Korea', '🇰🇷', [
    League('tsdb.5124', 'KBL', tsdb: 5124, sport: _bb),
    League('tsdb.4830', 'KBO League', tsdb: 4830, sport: _bsb),
  ]),
  Country('esp', 'Spain', '🇪🇸', [
    League('esp.1', 'LaLiga'),
    League('esp.2', 'LaLiga 2'),
    League('esp.copa_del_rey', 'Copa del Rey'),
    League('esp.w.1', 'Liga F'),
    League('tsdb.4408', 'Liga ACB', tsdb: 4408, sport: _bb),
    League('tsdb.5486', 'Liga Femenina', tsdb: 5486, sport: _bb),
  ]),
  // ESPN's Superettan feed (swe.2) has no fixtures.
  Country('swe', 'Sweden', '🇸🇪', [
    League('swe.1', 'Allsvenskan'),
    League('tsdb.4403', 'Superettan', tsdb: 4403),
    League('tsdb.5209', 'Damallsvenskan', tsdb: 5209),
  ]),
  Country('sui', 'Switzerland', '🇨🇭', [
    League('tsdb.4675', 'Super League', tsdb: 4675),
    League('tsdb.5940', "Women's Super League", tsdb: 5940),
  ]),
  Country('twn', 'Taiwan', '🇹🇼', [League('tsdb.5111', 'CPBL', tsdb: 5111, sport: _bsb)]),
  Country('tur', 'Turkey', '🇹🇷', [
    League('tur.1', 'Süper Lig'),
    League('tsdb.4475', 'Basketbol Süper Ligi', tsdb: 4475, sport: _bb),
  ]),
  Country('ukr', 'Ukraine', '🇺🇦', [League('tsdb.4354', 'Premier League', tsdb: 4354)]),
  Country('usa', 'United States', '🇺🇸', [
    League('usa.1', 'MLS'),
    League('usa.usl.1', 'USL Championship'),
    League('usa.open', 'U.S. Open Cup'),
    League('usa.nwsl', 'NWSL'),
    League('usa.w.usl.1', 'USL Super League (women)'),
    League('nba', 'NBA', sport: _bb),
    League('wnba', 'WNBA', sport: _bb),
    League('mens-college-basketball', 'NCAA Men', sport: _bb),
    League('womens-college-basketball', 'NCAA Women', sport: _bb),
    League('mlb', 'MLB', sport: _bsb),
    League('college-baseball', 'NCAA Baseball', sport: _bsb),
  ]),
  Country('uru', 'Uruguay', '🇺🇾', [League('uru.1', 'Primera División')]),
  Country('ven', 'Venezuela', '🇻🇪', [
    League('ven.1', 'Liga FUTVE'),
    League('tsdb.5112', 'LVBP', tsdb: 5112, sport: _bsb),
  ]),
];

/// The country a league belongs to (the first one listing it).
Country? countryOfLeague(String slug) {
  for (final c in countries) {
    if (c.leagues.any((l) => l.slug == slug)) return c;
  }
  return null;
}

League? leagueBySlug(String slug) {
  for (final c in countries) {
    for (final l in c.leagues) {
      if (l.slug == slug) return l;
    }
  }
  return null;
}

Country? countryByCode(String? code) {
  for (final c in countries) {
    if (c.code == code) return c;
  }
  return null;
}

/// Starting country from the phone's region (ISO 3166 alpha-2), else England.
Country defaultCountry(String? region) {
  const iso = {
    'AR': 'arg',
    'AU': 'aus',
    'AT': 'aut',
    'BE': 'bel',
    'BO': 'bol',
    'BR': 'bra',
    'CL': 'chi',
    'CN': 'chn',
    'CO': 'col',
    'CR': 'crc',
    'BG': 'bul',
    'CY': 'cyp',
    'HR': 'cro',
    'CA': 'can',
    'CU': 'cub',
    'IL': 'isr',
    'KR': 'kor',
    'PR': 'pur',
    'TW': 'twn',
    'EG': 'egy',
    'HU': 'hun',
    'IR': 'irn',
    'IE': 'irl',
    'LT': 'ltu',
    'PL': 'pol',
    'RO': 'rou',
    'RS': 'srb',
    'SK': 'svk',
    'UA': 'ukr',
    'DK': 'den',
    'EC': 'ecu',
    'GB': 'eng',
    'FR': 'fra',
    'DE': 'ger',
    'GR': 'gre',
    'GT': 'gua',
    'HN': 'hon',
    'IT': 'ita',
    'JP': 'jpn',
    'MX': 'mex',
    'NL': 'ned',
    'NO': 'nor',
    'PY': 'par',
    'PE': 'per',
    'PT': 'por',
    'SA': 'ksa',
    'ES': 'esp',
    'SE': 'swe',
    'CH': 'sui',
    'TR': 'tur',
    'US': 'usa',
    'UY': 'uru',
    'VE': 'ven',
  };
  return countryByCode(iso[region?.toUpperCase()]) ?? countryByCode('eng')!;
}

enum MatchState { scheduled, live, finished, other }

class Team {
  const Team(this.name, this.shortName, this.logo, this.score);
  final String name;
  final String shortName;
  final String? logo;
  final String? score;
}

/// 1X2 prices (decimal) from the bookmaker ESPN shows for the match.
class MatchOdds {
  const MatchOdds({
    required this.home,
    required this.draw,
    required this.away,
    this.provider = '',
    this.totalLine,
    this.over,
    this.under,
    this.extras = const [],
    this.opening,
  });
  final double? home;
  final double? draw;
  final double? away;
  final String provider;

  /// The same provider's first prices for this match, when the feed has
  /// them (ESPN's DraftKings lines carry `open` next to the current price).
  final MatchOdds? opening;

  /// Total goals line (2.5) with over / under prices, when offered.
  final double? totalLine;
  final double? over;
  final double? under;

  /// Other markets the provider prices, e.g. ('Double chance 1X', 1.36).
  final List<(String, double)> extras;

  bool get isEmpty => count == 0;
  int get count => [home, draw, away].where((p) => p != null).length;
}

class Match {
  const Match({
    required this.id,
    required this.league,
    required this.kickoff,
    required this.home,
    required this.away,
    required this.state,
    required this.detail,
    this.venue,
    this.odds,
  });
  final String id;
  final League league;
  final DateTime kickoff; // UTC
  final Team home;
  final Team away;
  final MatchState state;
  final String detail; // "FT", "67'", "Postponed"...
  final String? venue;
  final MatchOdds? odds;

  String get title => '${home.name} vs ${away.name}';

  /// The same match with a newer status and score from another feed.
  Match withStatus(MatchState state, String detail, String? homeScore, String? awayScore) => Match(
    id: id,
    league: league,
    kickoff: kickoff,
    home: Team(home.name, home.shortName, home.logo, homeScore ?? home.score),
    away: Team(away.name, away.shortName, away.logo, awayScore ?? away.score),
    state: state,
    detail: detail,
    venue: venue,
    odds: odds,
  );
  bool get hasScore => state == MatchState.live || state == MatchState.finished;

  /// A pending single bet on this match, for the bet form. Pass a pick
  /// (e.g. from the odds buttons) to pre-fill the selection and price.
  Bet toBetTemplate({String selection = '', double odds = 0, String? market}) => Bet(
    selection: selection,
    event: title,
    sport: league.knownSport.label,
    date: isoDate(kickoff.toLocal()),
    stake: 0,
    odds: odds,
    created: DateTime.now().toIso8601String(),
    market: market ?? (selection.isEmpty ? '' : marketOf(selection)),
    matchId: id,
    leagueSlug: league.slug,
    leagueName: league.name,
    kickoff: kickoff,
  );
}

/// Parses one ESPN scoreboard response. Unknown or malformed events are skipped.
List<Match> parseScoreboard(String body, League league) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) return const [];
  final out = <Match>[];
  for (final e in (json['events'] as List? ?? const [])) {
    try {
      final comp = (e['competitions'] as List).first as Map<String, dynamic>;
      final teams = (comp['competitors'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic> side(String s) => teams.firstWhere((t) => t['homeAway'] == s, orElse: () => teams.first);
      Team team(Map<String, dynamic> c) {
        final t = c['team'] as Map<String, dynamic>? ?? const {};
        final name = (t['displayName'] ?? t['name'] ?? '?') as String;
        return Team(name, (t['shortDisplayName'] ?? name) as String, t['logo'] as String?, c['score']?.toString());
      }

      final type = (e['status']?['type'] as Map<String, dynamic>?) ?? const {};
      final state = switch (type['state']) {
        'pre' => MatchState.scheduled,
        'in' => MatchState.live,
        'post' => type['completed'] == true ? MatchState.finished : MatchState.other,
        _ => MatchState.other,
      };
      out.add(
        Match(
          id: e['id'].toString(),
          league: league,
          kickoff: DateTime.parse(e['date'] as String).toUtc(),
          home: team(side('home')),
          away: team(side('away')),
          state: state,
          detail: (type['shortDetail'] ?? type['detail'] ?? '') as String,
          venue: comp['venue']?['fullName'] as String?,
          odds: _odds(comp['odds']),
        ),
      );
    } catch (_) {
      // Skip events we can't read rather than failing the whole day.
    }
  }
  return out;
}

/// Parses one TheSportsDB `eventsday` / `eventsnextleague` response.
/// Their times are UTC; scores come as strings or null.
List<Match> parseSportsDb(String body, League league) {
  final json = jsonDecode(body);
  final events = json is Map<String, dynamic> ? json['events'] : null;
  if (events is! List) return const [];
  final out = <Match>[];
  for (final e in events) {
    try {
      if (e is! Map<String, dynamic>) continue;
      final ts = e['strTimestamp'] as String? ?? '${e['dateEvent']}T${e['strTime'] ?? '00:00:00'}';
      final kickoff = DateTime.parse(RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(ts) ? ts : '${ts}Z').toUtc();
      final hs = e['intHomeScore']?.toString(), as = e['intAwayScore']?.toString();
      final (state, detail) = sportsDbStatus((e['strStatus'] ?? '') as String, hasScore: hs != null && as != null);
      Team team(String name, Object? badge, String? score) => Team(
        name,
        name,
        badge is String && badge.isNotEmpty ? badge : null,
        state == MatchState.scheduled ? null : score,
      );
      out.add(
        Match(
          id: 'tsdb:${e['idEvent']}',
          league: league,
          kickoff: kickoff,
          home: team(e['strHomeTeam'] as String, e['strHomeTeamBadge'], hs),
          away: team(e['strAwayTeam'] as String, e['strAwayTeamBadge'], as),
          state: state,
          detail: detail,
          venue: (e['strVenue'] as String?)?.trim().isEmpty ?? true ? null : e['strVenue'] as String,
        ),
      );
    } catch (_) {
      // Skip events we can't read.
    }
  }
  return out;
}

/// State and short detail for a TheSportsDB status code ("NS", "2H", "FT",
/// "PST"...; older events spell them out, e.g. "Match Finished").
(MatchState, String) sportsDbStatus(String raw, {bool hasScore = false}) {
  final s = raw.trim().toUpperCase();
  return switch (s) {
    '' || 'NS' || 'TBD' || 'NOT STARTED' => hasScore ? (MatchState.finished, 'FT') : (MatchState.scheduled, ''),
    '1H' || 'FIRST HALF' => (MatchState.live, '1st half'),
    'HT' || 'HALFTIME' || 'HALF TIME' => (MatchState.live, 'HT'),
    '2H' || 'SECOND HALF' => (MatchState.live, '2nd half'),
    'ET' || 'BT' || 'EXTRA TIME' => (MatchState.live, 'Extra time'),
    'P' || 'PEN_LIVE' || 'PENALTY IN PROGRESS' => (MatchState.live, 'Penalties'),
    'LIVE' || 'INT' || 'IN PLAY' => (MatchState.live, 'Live'),
    'FT' || 'MATCH FINISHED' || 'FINISHED' => (MatchState.finished, 'FT'),
    'AET' => (MatchState.finished, 'AET'),
    'PEN' || 'AP' => (MatchState.finished, 'FT (pens)'),
    'AWD' || 'WO' => (MatchState.finished, 'Awarded'),
    'PST' || 'POSTPONED' || 'MATCH POSTPONED' => (MatchState.other, 'Postponed'),
    'CANC' || 'CANCELLED' => (MatchState.other, 'Cancelled'),
    'ABD' || 'ABANDONED' => (MatchState.other, 'Abandoned'),
    'SUSP' => (MatchState.other, 'Suspended'),
    // Basketball quarters and overtime, baseball innings.
    'Q1' || 'Q2' || 'Q3' || 'Q4' || 'OT' => (MatchState.live, s),
    'AOT' => (MatchState.finished, 'AOT'),
    _ when RegExp(r'^(IN|TOP|BOT)\s?\d+$').hasMatch(s) => (MatchState.live, s),
    _ => hasScore ? (MatchState.finished, 'FT') : (MatchState.other, raw.trim()),
  };
}

/// ESPN's matches with TheSportsDB's filled in: a TheSportsDB match that is
/// already on ESPN in the same league (same teams, kick-off within a day,
/// so a women's match never folds into the men's) only updates its
/// status and score, since ESPN stops updating some leagues; the rest are
/// added as they are.
List<Match> mergeSportsDb(List<Match> espn, List<Match> tsdb) {
  final out = [...espn];
  for (final t in tsdb) {
    final i = out.indexWhere(
      (e) =>
          !e.id.startsWith('tsdb:') &&
          e.league.slug == t.league.slug &&
          e.kickoff.difference(t.kickoff).inHours.abs() <= 30 &&
          sameTeam(e.home.name, t.home.name) &&
          sameTeam(e.away.name, t.away.name),
    );
    if (i < 0) {
      out.add(t);
    } else if (t.state != MatchState.scheduled && out[i].state != t.state) {
      out[i] = out[i].withStatus(t.state, t.detail, t.home.score, t.away.score);
    }
  }
  return out;
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
};
const _filler = {
  'fc',
  'cf',
  'cd',
  'sc',
  'ac',
  'afc',
  'club',
  'deportes',
  'deportivo',
  'de',
  'del',
  'la',
  'el',
  'the',
  'kv',
  'kvc',
  'krc',
  'kaa',
  'rsc',
  'royal',
  'sk',
  'ksv',
  'and',
  'y',
};

Set<String> _teamWords(String name) {
  final plain = name.toLowerCase().split('').map((c) => _accents[c] ?? c).join();
  return plain.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1 && !_filler.contains(w)).toSet();
}

/// The two teams in a pick's event text: "A vs B", "A v B", "A - B", "A @ B".
(String, String)? splitEvent(String event) {
  final parts = event.split(RegExp(r'\s+(?:vs\.?|v|-|–|—|@|x)\s+', caseSensitive: false));
  if (parts.length != 2) return null;
  final a = parts[0].trim(), b = parts[1].trim();
  return a.isEmpty || b.isEmpty ? null : (a, b);
}

/// Whether two feeds' names for a team are the same club, e.g.
/// "Deportes Limache" and "Limache", or "Ñublense" and "Nublense".
bool sameTeam(String a, String b) {
  final wa = _teamWords(a), wb = _teamWords(b);
  if (wa.isEmpty || wb.isEmpty) return a.toLowerCase().trim() == b.toLowerCase().trim();
  final common = wa.intersection(wb).length;
  return common == wa.length || common == wb.length || common >= 2;
}

/// Best entry of ESPN's `odds` list (often `[null]` or missing): the
/// provider with the most of home / draw / away priced.
MatchOdds? _odds(Object? raw) {
  MatchOdds? best;
  for (final o in parseOddsList(raw)) {
    if (best == null || o.count > best.count) best = o;
  }
  return best;
}

/// Every provider in an ESPN `odds` / `pickcenter` list that prices at least
/// one outcome. ESPN mixes several shapes, sometimes within one response:
///   homeTeamOdds.value (decimal)            Bet 365 on the scoreboard
///   homeTeamOdds.odds.value / .summary      Bet 365 on the match summary
///   homeTeamOdds.moneyLine (American)       DraftKings
///   moneyline.home.close.odds ("+130")      DraftKings, newer feeds
List<MatchOdds> parseOddsList(Object? raw) {
  if (raw is! List) return const [];
  final out = <MatchOdds>[];
  for (final o in raw) {
    if (o is! Map<String, dynamic>) continue;
    double? price(String sideKey, String lineKey) {
      final side = o[sideKey];
      if (side is Map) {
        final d =
            _decimal(side['value']) ??
            _decimal(side['odds'] is Map ? side['odds']['value'] : null) ??
            _fractional(side['summary']) ??
            _fractional(side['odds'] is Map ? side['odds']['summary'] : null) ??
            _american(side['moneyLine']);
        if (d != null) return d;
      }
      final line = o['moneyline'] is Map ? o['moneyline'][lineKey] : null;
      if (line is Map) {
        for (final k in const ['current', 'close', 'open']) {
          final v = line[k] is Map ? line[k]['odds'] : null;
          final d = _american(v);
          if (d != null) return d;
        }
      }
      return null;
    }

    double? total(String side) {
      final v = o['total'] is Map ? o['total'][side] : null;
      if (v is! Map) return null;
      for (final k in const ['current', 'close', 'open']) {
        final d = _american(v[k] is Map ? v[k]['odds'] : null);
        if (d != null) return d;
      }
      return null;
    }

    double? totalLine() {
      final n = o['overUnder'];
      if (n is num && n > 0) return n.toDouble();
      final v = o['total'] is Map && o['total']['over'] is Map ? o['total']['over'] : null;
      for (final k in const ['current', 'close', 'open']) {
        final l = v is Map && v[k] is Map ? v[k]['line'] : null;
        final d = double.tryParse('${l ?? ''}'.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (d != null && d > 0) return d;
      }
      return null;
    }

    // Bet 365's extra markets on the match summary.
    final team = o['bettingOdds'] is Map ? o['bettingOdds']['teamOdds'] : null;
    double? market(String key) => team is Map && team[key] is Map ? _fractional(team[key]['value']) : null;
    final goalLine = team is Map && team['preMatchOverUnderHandicap'] is Map
        ? team['preMatchOverUnderHandicap']['value']?.toString()
        : null;
    final extras = <(String, double)>[
      for (final (label, key) in const [
        ('Double chance 1X', 'preMatchDoubleChanceHomeOrDraw'),
        ('Double chance 12', 'preMatchDoubleChanceHomeOrAway'),
        ('Double chance X2', 'preMatchDoubleChanceDrawOrAway'),
      ])
        if (market(key) case final p?) (label, p),
      if (goalLine != null) ...[
        if (market('preMatchGoalLineOver') case final p?) ('Over $goalLine goals', p),
        if (market('preMatchGoalLineUnder') case final p?) ('Under $goalLine goals', p),
      ],
    ];

    double? open(String market, String side) {
      final v = o[market] is Map ? o[market][side] : null;
      return _american(v is Map && v['open'] is Map ? v['open']['odds'] : null);
    }

    final opening = MatchOdds(
      home: open('moneyline', 'home'),
      draw: open('moneyline', 'draw'),
      away: open('moneyline', 'away'),
      over: open('total', 'over'),
      under: open('total', 'under'),
    );
    final odds = MatchOdds(
      opening: opening.isEmpty ? null : opening,
      home: price('homeTeamOdds', 'home'),
      draw: price('drawOdds', 'draw'),
      away: price('awayTeamOdds', 'away'),
      provider: (o['provider']?['displayName'] ?? o['provider']?['name'] ?? '') as String,
      totalLine: totalLine(),
      over: _american(o['overOdds']) ?? total('over'),
      under: _american(o['underOdds']) ?? total('under'),
      extras: extras,
    );
    if (!odds.isEmpty) out.add(odds);
  }
  return out;
}

double? _decimal(Object? v) {
  final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  return d != null && d > 1 ? d : null;
}

/// "13/10" -> 2.3
double? _fractional(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)\s*$').firstMatch(v);
  if (m == null) return null;
  final n = double.parse(m.group(1)!), d = double.parse(m.group(2)!);
  return d == 0 ? null : 1 + n / d;
}

/// American moneyline (130, "-165", "+130", "EVEN") -> decimal.
double? _american(Object? v) {
  if (v is String && v.trim().toUpperCase() == 'EVEN') return 2;
  final a = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll('+', '').trim());
  if (a == null || a.abs() < 100) return null;
  return a > 0 ? 1 + a / 100 : 1 + 100 / -a;
}

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// The dates a feed files [day]'s matches under (the phone's midnight to
/// midnight, seen at UTC offset [offsetHours] for that moment): one or two.
List<DateTime> _feedDates(DateTime day, int Function(DateTime utc) offsetHours) {
  DateTime at(DateTime local) {
    final utc = local.toUtc();
    final t = utc.add(Duration(hours: offsetHours(utc)));
    return DateTime(t.year, t.month, t.day);
  }

  final a = at(DateTime(day.year, day.month, day.day));
  final b = at(DateTime(day.year, day.month, day.day + 1).subtract(const Duration(minutes: 1)));
  return a == b ? [a] : [a, b];
}

/// ESPN files matches under their US Eastern date.
List<DateTime> espnDatesFor(DateTime day) => _feedDates(day, _easternOffset);

/// TheSportsDB files matches under their UTC date.
List<DateTime> sportsDbDatesFor(DateTime day) => _feedDates(day, (_) => 0);

/// US Eastern offset: daylight time from the second Sunday of March to the
/// first Sunday of November.
int _easternOffset(DateTime utc) {
  DateTime sunday(int month, int nth) {
    final first = DateTime.utc(utc.year, month);
    return DateTime.utc(utc.year, month, 1 + (7 - first.weekday) % 7 + 7 * (nth - 1));
  }

  final from = sunday(3, 2).add(const Duration(hours: 7)), to = sunday(11, 1).add(const Duration(hours: 6));
  return !utc.isBefore(from) && utc.isBefore(to) ? -4 : -5;
}

class FixturesApi {
  FixturesApi({http.Client? client, int tsdbPerMinute = 25, this.retryDelay = const Duration(seconds: 1)})
    : _client = client ?? http.Client(),
      _tsdbGate = RequestGate(2, perMinute: tsdbPerMinute, reserve: 12);
  final http.Client _client;

  /// Wait before trying a dropped request again.
  final Duration retryDelay;

  /// A few requests at a time per feed; see [RequestGate].
  final _espnGate = RequestGate(8, urgentSlots: 3);
  final RequestGate _tsdbGate;

  /// TheSportsDB answers, by URL, kept five minutes: its free feed allows
  /// few requests, so the same list is read once.
  final _tsdbBodies = <String, (DateTime, String)>{};

  /// Requests on their way, and whether they were urgent.
  final _tsdbPending = <String, (bool, Future<String?>)>{};

  /// One feed request through its gate. Null when it failed; throws
  /// [GateFull] when a background TheSportsDB request was skipped.
  Future<String?> _get(String url, {bool urgent = false}) {
    if (!url.startsWith(_tsdb)) {
      return _fetch(_espnGate, url, urgent: urgent).catchError((Object _) => null, test: (e) => e is Throttled);
    }
    final hit = _tsdbBodies[url];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 5)) return Future.value(hit.$2);
    // What's on screen never waits behind, or is skipped with, a background
    // request for the same list.
    final pending = _tsdbPending[url];
    if (pending != null && (pending.$1 || !urgent)) return pending.$2;
    Future<String?> load() async {
      try {
        return await _fetch(_tsdbGate, url, urgent: urgent);
      } on Throttled {
        // Cloudflare turns every request away for a while (its 1015).
        _tsdbGate.pause(const Duration(minutes: 1));
        if (!urgent) throw const GateFull();
        try {
          return await _fetch(_tsdbGate, url, urgent: true);
        } on Throttled {
          return null;
        }
      }
    }

    final started = load().then((body) {
      if (body != null) _tsdbBodies[url] = (DateTime.now(), body);
      return body;
    });
    _tsdbPending[url] = (urgent, started);
    return started.whenComplete(() {
      if (_tsdbPending[url]?.$2 == started) _tsdbPending.remove(url);
    });
  }

  /// [_fetchOnce] through [gate], tried again once after [retryDelay] when
  /// the connection dropped or hung: phones drop them (a reused one the
  /// server closed, a handshake cut short) even with full signal, and now and
  /// then a feed sits on a request for half a minute. The wait holds no place
  /// in the gate.
  Future<String?> _fetch(RequestGate gate, String url, {required bool urgent}) async {
    try {
      return await gate.run(() => _fetchOnce(url, const Duration(seconds: 8)), urgent: urgent);
    } on _Dropped {
      await Future<void>.delayed(retryDelay);
      try {
        return await gate.run(() => _fetchOnce(url, const Duration(seconds: 15)), urgent: urgent);
      } on _Dropped {
        return null;
      }
    }
  }

  /// One try at [url]: the body, or null for an answer that won't change
  /// (400, 404). Throws [Throttled] on a 429, and [_Dropped] when another
  /// try could help: no answer within [timeout], or a 5xx.
  Future<String?> _fetchOnce(String url, Duration timeout) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse(url)).timeout(timeout);
    } catch (_) {
      throw const _Dropped();
    }
    if (res.statusCode == 200) return utf8.decode(res.bodyBytes);
    if (res.statusCode == 429) throw const Throttled();
    if (res.statusCode >= 500) throw const _Dropped();
    return null;
  }

  final _cache = <String, (DateTime, List<Match>)>{};

  static const _espn = 'https://site.api.espn.com/apis/site/v2/sports';

  /// [league]'s ESPN feed, e.g. `.../sports/soccer/eng.1`.
  static String _feed(League league) => '$_espn/${league.knownSport.espn}/${league.slug}';

  /// TheSportsDB's free feed; 123 is its public key.
  static const _tsdb = 'https://www.thesportsdb.com/api/v1/json/123';

  /// Each TheSportsDB league's round lists (see [_sportsDb]), kept an hour.
  final _tsdbRounds = <int, (DateTime, List<String>)>{};

  /// The lists of the round with [id]'s last result and the round with its
  /// next fixture (often the same one). Empty when they couldn't be read.
  Future<List<String>> _roundUrls(int id, {bool urgent = false}) async {
    final hit = _tsdbRounds[id];
    if (hit != null && DateTime.now().difference(hit.$1) < const Duration(hours: 1)) return hit.$2;
    final bodies = await Future.wait([
      for (final kind in ['eventspastleague', 'eventsnextleague']) _get('$_tsdb/$kind.php?id=$id', urgent: urgent),
    ]);
    if (bodies.every((b) => b == null)) return const [];
    final urls = <String>{};
    for (final body in bodies) {
      try {
        final events = body == null ? null : jsonDecode(body)['events'];
        if (events is! List || events.isEmpty) continue;
        final e = events.first as Map<String, dynamic>;
        final round = e['intRound']?.toString(), season = e['strSeason']?.toString();
        if (round == null || season == null || round.isEmpty || season.isEmpty) continue;
        urls.add('$_tsdb/eventsround.php?id=$id&r=$round&s=${Uri.encodeQueryComponent(season)}');
      } catch (_) {
        // An answer we can't read: fall back to the day lists.
      }
    }
    final list = urls.toList();
    if (bodies.every((b) => b != null)) _tsdbRounds[id] = (DateTime.now(), list);
    return list;
  }

  /// [league]'s TheSportsDB matches for the UTC [dates]: each date's day
  /// list, and when one is full (the free key cuts it at three matches) the
  /// whole rounds around now too: the one with the league's last result and
  /// the one with its next fixture. Null when nothing could be read; throws
  /// [GateFull] when only skipped requests were left.
  Future<List<Match>?> _sportsDb(League league, List<DateTime> dates, {bool urgent = false}) async {
    var skipped = false;
    Future<String?> get(String url) async {
      try {
        return await _get(url, urgent: urgent);
      } on GateFull {
        skipped = true;
        return null;
      }
    }

    final id = league.tsdb!;
    final out = <Match>[];
    var read = false, full = false;
    for (final body in await Future.wait([for (final d in dates) get('$_tsdb/eventsday.php?d=${_isoDay(d)}&l=$id')])) {
      if (body == null) continue;
      read = true;
      final day = parseSportsDb(body, league);
      full |= day.length >= _tsdbDayCap;
      out.addAll(day);
    }
    if (full) {
      List<String> rounds;
      try {
        rounds = await _roundUrls(id, urgent: urgent);
      } on GateFull {
        rounds = const [];
      }
      for (final body in await Future.wait(rounds.map(get))) {
        if (body != null) out.addAll(parseSportsDb(body, league));
      }
    }
    if (!read && skipped) throw const GateFull();
    if (!read) return null;
    final seen = <String>{};
    return [
      for (final m in out)
        if (seen.add(m.id)) m,
    ];
  }

  /// Most matches a free TheSportsDB day list returns.
  static const _tsdbDayCap = 3;

  /// Reads every ESPN (league, url) and TheSportsDB (league, UTC dates)
  /// request through the gates. Returns the ESPN and TheSportsDB matches,
  /// and false when every request failed. [urgent] requests (what's on
  /// screen) go before background ones; the slugs of leagues that couldn't
  /// be read (failed, or a background request skipped) go in [unread].
  Future<(List<Match>, List<Match>, bool)> _fetchAll(
    List<(League, String)> espn, {
    List<(League, List<DateTime>)> tsdb = const [],
    bool urgent = false,
    Set<String>? unread,
  }) async {
    var failures = 0, skips = 0;
    Future<List<Match>> read(League league, Future<List<Match>?> Function() job) async {
      List<Match>? list;
      try {
        list = await job();
      } on GateFull {
        skips++;
        unread?.add(league.slug);
        return const [];
      } catch (_) {
        list = null;
      }
      if (list == null) {
        failures++;
        unread?.add(league.slug);
        return const [];
      }
      return list;
    }

    final results = await Future.wait([
      for (final (league, url) in espn)
        read(league, () async {
          final body = await _get(url, urgent: urgent);
          return body == null ? null : parseScoreboard(body, league);
        }),
      for (final (league, dates) in tsdb) read(league, () => _sportsDb(league, dates, urgent: urgent)),
    ]);
    final total = results.length;
    return (
      [for (final ms in results.take(espn.length)) ...ms],
      [for (final ms in results.skip(espn.length)) ...ms],
      // Skipped requests aren't failures: all skipped is an empty answer.
      skips == total || failures < total - skips,
    );
  }

  /// Matches kicking off on [day] in the phone's time zone, grouped feed-wide.
  /// ESPN files matches by US Eastern date and TheSportsDB by UTC date, so
  /// each feed is read for the dates the local day overlaps and filtered
  /// locally. Only [country]'s leagues in [sport] are read (all of them
  /// when null). Throws only if every request failed.
  Future<List<Match>> matches(Country country, DateTime day, {Sport? sport, bool refresh = false}) async {
    final local = DateTime(day.year, day.month, day.day);
    final leagues = country.leaguesIn(sport);
    final key = '${country.code}-${sport?.name ?? 'all'}-${_ymd(local)}';
    final hit = _cache[key];
    if (!refresh && hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 2)) return hit.$2;

    final (espn, tsdb, ok) = await _fetchAll(
      urgent: true,
      [
        for (final l in leagues)
          if (l.onEspn)
            for (final d in espnDatesFor(local)) (l, '${_feed(l)}/scoreboard?dates=${_ymd(d)}'),
      ],
      tsdb: [
        for (final l in leagues)
          if (l.tsdb != null) (l, sportsDbDatesFor(local)),
      ],
    );
    if (!ok) {
      throw const FixturesException("Couldn't load matches. Check your connection and try again.");
    }
    final results = [mergeSportsDb(espn, tsdb)];
    final seen = <String>{};
    final list =
        [
          for (final m in results.expand((r) => r))
            if (seen.add(m.id) && _sameDay(m.kickoff.toLocal(), local)) m,
        ]..sort((a, b) {
          final c = a.kickoff.compareTo(b.kickoff);
          return c != 0 ? c : a.home.name.compareTo(b.home.name);
        });
    _cache[key] = (DateTime.now(), list);
    return list;
  }

  /// The latest version of each of [saved] (starred matches), by id, read
  /// from its league's list for its day. Matches no feed has are left out.
  Future<Map<String, Match>> refreshMatches(List<Match> saved, {bool refresh = false}) async {
    final groups = <String, (League, DateTime)>{};
    for (final m in saved) {
      final d = m.kickoff.toLocal();
      groups['${m.league.slug}|${_ymd(d)}'] = (m.league, DateTime(d.year, d.month, d.day));
    }
    final out = <String, Match>{};
    await Future.wait([
      for (final (l, d) in groups.values)
        () async {
          try {
            final list = await matches(Country('league:${l.slug}', l.name, '', [l]), d, refresh: refresh);
            for (final m in list) {
              out[m.id] = m;
            }
          } on FixturesException {
            // Keep what was saved for this league.
          }
        }(),
    ]);
    return out;
  }

  final _days = <String, (DateTime, List<Match>, Set<String>)>{};

  /// Every match ESPN files under [day] in all the leagues the app knows,
  /// plus TheSportsDB's for its leagues unless [withTsdb] is false. Cached for
  /// ten minutes. ESPN's scoreboard takes one day at a time; a date range is
  /// rejected. TheSportsDB's free key allows about 30 requests a minute, so
  /// callers ask it for as few days as they can. Leagues that couldn't be
  /// read go in [unread], and then the day is kept only a minute.
  Future<List<Match>> _allOn(
    DateTime day, {
    Sport sport = Sport.soccer,
    bool withEspn = true,
    bool withTsdb = true,
    Set<String>? unread,
  }) async {
    final key = '${sport.name}-${_ymd(day)}${withEspn ? '-espn' : ''}${withTsdb ? '-tsdb' : ''}';
    final hit = _days[key];
    if (hit != null &&
        DateTime.now().difference(hit.$1) < (hit.$3.isEmpty ? const Duration(minutes: 10) : const Duration(minutes: 1))) {
      unread?.addAll(hit.$3);
      return hit.$2;
    }
    final missed = <String>{};
    final leagues = {
      for (final c in countries)
        for (final l in c.leaguesIn(sport)) l.slug: l,
    }.values;
    final (espn, tsdb, ok) = await _fetchAll(
      [
        for (final l in leagues)
          if (withEspn && l.onEspn) (l, '${_feed(l)}/scoreboard?dates=${_ymd(day)}'),
      ],
      tsdb: [
        for (final l in leagues)
          if (withTsdb && l.tsdb != null) (l, [day]),
      ],
      unread: missed,
    );
    if (!ok) throw const FixturesException("Couldn't load matches. Check your connection and try again.");
    final list = mergeSportsDb(espn, tsdb);
    unread?.addAll(missed);
    _days[key] = (DateTime.now(), list, missed);
    return list;
  }

  /// The days searched for a pick's match, nearest first: picks are mostly
  /// for today and the next few days. TheSportsDB is only read for the
  /// first two.
  static const _searchDays = [0, 1, -1, 2, 3, 4];

  /// The real match for a pick's event text ("Fiorentina vs Como", "A - B"),
  /// the one nearest to now when a fixture repeats. Null when not found.
  Future<Match?> findMatch(String event) async {
    final teams = splitEvent(event);
    if (teams == null) return null;
    final now = DateTime.now();
    var reached = false;
    for (final offset in _searchDays) {
      final List<Match> list;
      try {
        list = await _allOn(DateTime(now.year, now.month, now.day + offset), withTsdb: offset == 0 || offset == 1);
        reached = true;
      } on FixturesException {
        continue;
      }
      for (final m in list) {
        final same = sameTeam(m.home.name, teams.$1) && sameTeam(m.away.name, teams.$2);
        final swapped = sameTeam(m.home.name, teams.$2) && sameTeam(m.away.name, teams.$1);
        if (same || swapped) return m;
      }
    }
    if (!reached) throw const FixturesException("Couldn't load matches. Check your connection and try again.");
    return null;
  }

  final _live = <Sport, _LiveState>{};

  /// Every [sport] match being played right now across all the leagues the
  /// app knows, sorted alphabetically. Cached for 30 seconds. Every league is
  /// read once every ten minutes (or when [full]); in between, only the
  /// leagues with a match live or about to kick off, so refreshing every
  /// minute stays a handful of requests. A league that can't be read keeps
  /// the matches it had, so a dropped request never empties part of the list.
  Future<List<Match>> liveMatches({Sport sport = Sport.soccer, bool refresh = false, bool full = false}) async {
    final st = _live.putIfAbsent(sport, _LiveState.new);
    final hit = st.list;
    if (!refresh && !full && hit != null && DateTime.now().difference(hit.$1) < const Duration(seconds: 30)) {
      return hit.$2;
    }
    final now = DateTime.now();
    final last = st.full;
    final everything = full || last == null || now.difference(last) >= const Duration(minutes: 10);
    final leagues = {
      for (final c in countries)
        for (final l in c.leaguesIn(sport))
          if (everything || st.leagues.contains(l.slug)) l.slug: l,
    }.values;
    // TheSportsDB has no free live feed, so read today's (UTC) matches, and
    // yesterday's early in the UTC day: evening kick-offs in the Americas
    // cross midnight UTC. Its answers are kept five minutes.
    final today = now.toUtc();
    final tsdbDays = [if (today.hour < 8) today.subtract(const Duration(days: 1)), today];
    final unread = <String>{};
    final (espn, tsdb, ok) = await _fetchAll(
      [
        for (final l in leagues)
          if (l.onEspn) (l, '${_feed(l)}/scoreboard'),
      ],
      tsdb: [
        for (final l in leagues)
          if (l.tsdb != null) (l, tsdbDays),
      ],
      unread: unread,
    );
    if (!ok && st.byLeague.isEmpty) {
      throw const FixturesException("Couldn't load live matches. Check your connection and try again.");
    }
    if (everything && ok) st.full = now;
    final fresh = <String, List<Match>>{
      for (final l in leagues)
        if (!unread.contains(l.slug)) l.slug: [],
    };
    for (final m in mergeSportsDb(espn, tsdb)) {
      fresh[m.league.slug]?.add(m);
    }
    st.byLeague.addAll(fresh);
    final all = st.byLeague.values.expand((ms) => ms);
    final soon = now.add(const Duration(minutes: 15)), started = now.subtract(const Duration(hours: 4));
    st.leagues = {
      // Couldn't be read: try again on the next refresh.
      ...unread,
      for (final m in all)
        if (m.state == MatchState.live ||
            (m.state == MatchState.scheduled && m.kickoff.isBefore(soon) && m.kickoff.isAfter(started)))
          m.league.slug,
    };
    final seen = <String>{};
    final list = [
      for (final m in all)
        if (m.state == MatchState.live && seen.add(m.id)) m,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    st.list = (DateTime.now(), list);
    return list;
  }

  final _details = <String, (DateTime, MatchDetails)>{};

  /// The match page's data from ESPN's summary feed. Cached for a minute.
  Future<MatchDetails> details(Match m, {bool refresh = false}) async {
    final hit = _details[m.id];
    if (!refresh && hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 1)) return hit.$2;
    // Matches only TheSportsDB has: just the status and score it gave.
    if (m.id.startsWith('tsdb:')) return MatchDetails.statusOf(m);
    try {
      final res = await _espnGate.run(
        urgent: true,
        () => _client.get(Uri.parse('${_feed(m.league)}/summary?event=${m.id}')).timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode != 200) throw FixturesException('ESPN answered ${res.statusCode}');
      var d = parseMatchDetails(utf8.decode(res.bodyBytes));
      // ESPN never moves some leagues past "scheduled"; trust the score
      // TheSportsDB gave the match list.
      if (d.state == MatchState.scheduled && (m.state == MatchState.live || m.state == MatchState.finished)) {
        d = d.withStatusOf(m);
      }
      _details[m.id] = (DateTime.now(), d);
      return d;
    } on FixturesException {
      rethrow;
    } catch (_) {
      throw const FixturesException("Couldn't load this match. Check your connection and try again.");
    }
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

/// What [FixturesApi.liveMatches] knows about one sport: when every league
/// was last read, the leagues that could have a match live until the next
/// full read, each league's matches as last read, and the last answer.
class _LiveState {
  DateTime? full;
  var leagues = <String>{};
  final byLeague = <String, List<Match>>{};
  (DateTime, List<Match>)? list;
}

/// A request worth trying again.
class _Dropped implements Exception {
  const _Dropped();
}

class FixturesException implements Exception {
  const FixturesException(this.message);
  final String message;
  @override
  String toString() => message;
}
