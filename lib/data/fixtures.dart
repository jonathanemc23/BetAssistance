import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/markets.dart';
import 'match_details.dart';
import 'models.dart';

export 'match_details.dart';

/// Football fixtures from ESPN's public scoreboard feed
/// (site.api.espn.com, free and keyless). One request per league and day.
/// Leagues ESPN lacks or doesn't keep up to date also read TheSportsDB's free
/// feed (thesportsdb.com), see [League.tsdb].
class League {
  const League(this.slug, this.name, {this.tsdb});
  final String slug;
  final String name;

  /// TheSportsDB league id. Its results fill in scores ESPN never updates
  /// (Chile), and leagues with a `tsdb.` slug come only from there
  /// (Belgian Cup).
  final int? tsdb;

  bool get onEspn => !slug.startsWith('tsdb.');
}

class Country {
  const Country(this.code, this.name, this.flag, this.leagues);
  final String code;
  final String name;
  final String flag;
  final List<League> leagues;
}

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
  ]),
  Country('arg', 'Argentina', '🇦🇷', [
    League('arg.1', 'Liga Profesional'),
    League('arg.2', 'Primera Nacional'),
    League('arg.copa', 'Copa Argentina'),
  ]),
  Country('aus', 'Australia', '🇦🇺', [League('aus.1', 'A-League')]),
  Country('aut', 'Austria', '🇦🇹', [League('aut.1', 'Bundesliga')]),
  Country('bel', 'Belgium', '🇧🇪', [League('bel.1', 'Pro League'), League('tsdb.5831', 'Belgian Cup', tsdb: 5831)]),
  Country('bol', 'Bolivia', '🇧🇴', [League('bol.1', 'División Profesional')]),
  Country('bra', 'Brazil', '🇧🇷', [
    League('bra.1', 'Série A'),
    League('bra.2', 'Série B'),
    League('bra.3', 'Série C'),
    League('bra.copa_do_brazil', 'Copa do Brasil'),
  ]),
  Country('chi', 'Chile', '🇨🇱', [
    League('chi.1', 'Primera División', tsdb: 4627),
    League('chi.copa_chi', 'Copa Chile', tsdb: 5378),
  ]),
  Country('chn', 'China', '🇨🇳', [League('chn.1', 'Super League')]),
  // ESPN's Primera B feed (col.2) has had no fixtures since 2025; it stays
  // listed so matches show up again if ESPN resumes it.
  Country('col', 'Colombia', '🇨🇴', [
    League('col.1', 'Primera A'),
    League('col.2', 'Primera B'),
    League('col.copa', 'Copa Colombia'),
  ]),
  Country('crc', 'Costa Rica', '🇨🇷', [League('crc.1', 'Primera División')]),
  Country('den', 'Denmark', '🇩🇰', [League('den.1', 'Superliga')]),
  Country('ecu', 'Ecuador', '🇪🇨', [League('ecu.1', 'LigaPro'), League('ecu.2', 'Serie B')]),
  Country('eng', 'England', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', [
    League('eng.1', 'Premier League'),
    League('eng.2', 'Championship'),
    League('eng.3', 'League One'),
    League('eng.4', 'League Two'),
    League('eng.5', 'National League'),
    League('eng.fa', 'FA Cup'),
    League('eng.league_cup', 'EFL Cup'),
    League('eng.w.1', "Women's Super League"),
  ]),
  Country('fra', 'France', '🇫🇷', [
    League('fra.1', 'Ligue 1'),
    League('fra.2', 'Ligue 2'),
    League('fra.coupe_de_france', 'Coupe de France'),
  ]),
  Country('ger', 'Germany', '🇩🇪', [
    League('ger.1', 'Bundesliga'),
    League('ger.2', '2. Bundesliga'),
    League('ger.3', '3. Liga'),
    League('ger.dfb_pokal', 'DFB-Pokal'),
  ]),
  Country('gre', 'Greece', '🇬🇷', [League('gre.1', 'Super League')]),
  Country('gua', 'Guatemala', '🇬🇹', [League('gua.1', 'Liga Nacional')]),
  Country('hon', 'Honduras', '🇭🇳', [League('hon.1', 'Liga Nacional')]),
  Country('ita', 'Italy', '🇮🇹', [
    League('ita.1', 'Serie A'),
    League('ita.2', 'Serie B'),
    League('ita.coppa_italia', 'Coppa Italia'),
  ]),
  Country('jpn', 'Japan', '🇯🇵', [League('jpn.1', 'J1 League')]),
  Country('mex', 'Mexico', '🇲🇽', [League('mex.1', 'Liga MX'), League('mex.2', 'Liga de Expansión')]),
  Country('ned', 'Netherlands', '🇳🇱', [
    League('ned.1', 'Eredivisie'),
    League('ned.2', 'Eerste Divisie'),
    League('ned.cup', 'KNVB Cup'),
  ]),
  Country('nor', 'Norway', '🇳🇴', [League('nor.1', 'Eliteserien')]),
  Country('par', 'Paraguay', '🇵🇾', [League('par.1', 'Primera División')]),
  Country('per', 'Peru', '🇵🇪', [League('per.1', 'Liga 1')]),
  Country('por', 'Portugal', '🇵🇹', [
    League('por.1', 'Primeira Liga'),
    League('por.taca.portugal', 'Taça de Portugal'),
  ]),
  Country('ksa', 'Saudi Arabia', '🇸🇦', [League('ksa.1', 'Pro League')]),
  Country('sco', 'Scotland', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', [League('sco.1', 'Premiership'), League('sco.2', 'Championship')]),
  Country('esp', 'Spain', '🇪🇸', [
    League('esp.1', 'LaLiga'),
    League('esp.2', 'LaLiga 2'),
    League('esp.copa_del_rey', 'Copa del Rey'),
  ]),
  Country('swe', 'Sweden', '🇸🇪', [League('swe.1', 'Allsvenskan')]),
  Country('sui', 'Switzerland', '🇨🇭', [League('sui.1', 'Super League')]),
  Country('tur', 'Turkey', '🇹🇷', [League('tur.1', 'Süper Lig')]),
  Country('usa', 'United States', '🇺🇸', [
    League('usa.1', 'MLS'),
    League('usa.usl.1', 'USL Championship'),
    League('usa.open', 'U.S. Open Cup'),
    League('usa.nwsl', 'NWSL'),
  ]),
  Country('uru', 'Uruguay', '🇺🇾', [League('uru.1', 'Primera División')]),
  Country('ven', 'Venezuela', '🇻🇪', [League('ven.1', 'Liga FUTVE')]),
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
    sport: 'Soccer',
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
    _ => hasScore ? (MatchState.finished, 'FT') : (MatchState.other, raw.trim()),
  };
}

/// ESPN's matches with TheSportsDB's filled in: a TheSportsDB match that is
/// already on ESPN (same teams, kick-off within a day) only updates its
/// status and score, since ESPN stops updating some leagues; the rest are
/// added as they are.
List<Match> mergeSportsDb(List<Match> espn, List<Match> tsdb) {
  final out = [...espn];
  for (final t in tsdb) {
    final i = out.indexWhere(
      (e) =>
          !e.id.startsWith('tsdb:') &&
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

class FixturesApi {
  FixturesApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, (DateTime, List<Match>)>{};

  static const _base = 'https://site.api.espn.com/apis/site/v2/sports/soccer';

  /// TheSportsDB's free feed; 123 is its public key.
  static const _tsdb = 'https://www.thesportsdb.com/api/v1/json/123';

  /// Runs every (league, isTheSportsDb, url) request at once. Returns the
  /// ESPN and TheSportsDB matches, and false when every request failed.
  Future<(List<Match>, List<Match>, bool)> _fetchAll(List<(League, bool, String)> requests) async {
    var failures = 0;
    final results = await Future.wait([
      for (final (league, isTsdb, url) in requests)
        () async {
          try {
            final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
            if (res.statusCode != 200) {
              failures++;
              return (isTsdb, const <Match>[]);
            }
            final body = utf8.decode(res.bodyBytes);
            return (isTsdb, isTsdb ? parseSportsDb(body, league) : parseScoreboard(body, league));
          } catch (_) {
            failures++;
            return (isTsdb, const <Match>[]);
          }
        }(),
    ]);
    return (
      [
        for (final (t, ms) in results)
          if (!t) ...ms,
      ],
      [
        for (final (t, ms) in results)
          if (t) ...ms,
      ],
      requests.isEmpty || failures < requests.length,
    );
  }

  /// Matches kicking off on [day] in the phone's time zone, grouped feed-wide.
  /// ESPN buckets matches by US Eastern date, so the day before and after are
  /// fetched too and filtered locally. Throws only if every request failed.
  Future<List<Match>> matches(Country country, DateTime day, {bool refresh = false}) async {
    final local = DateTime(day.year, day.month, day.day);
    final key = '${country.code}-${_ymd(local)}';
    final hit = _cache[key];
    if (!refresh && hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 2)) return hit.$2;

    final days = [local.subtract(const Duration(days: 1)), local, local.add(const Duration(days: 1))];
    final (espn, tsdb, ok) = await _fetchAll([
      for (final l in country.leagues)
        for (final d in days) ...[
          if (l.onEspn) (l, false, '$_base/${l.slug}/scoreboard?dates=${_ymd(d)}'),
          if (l.tsdb != null) (l, true, '$_tsdb/eventsday.php?d=${_isoDay(d)}&l=${l.tsdb}'),
        ],
    ]);
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

  (DateTime, List<Match>)? _live;

  /// Every match being played right now across all the leagues the app
  /// knows, sorted alphabetically. Cached for 30 seconds.
  Future<List<Match>> liveMatches({bool refresh = false}) async {
    final hit = _live;
    if (!refresh && hit != null && DateTime.now().difference(hit.$1) < const Duration(seconds: 30)) return hit.$2;
    final leagues = {
      for (final c in countries)
        for (final l in c.leagues) l.slug: l,
    }.values;
    // TheSportsDB has no free live feed, so read today's and yesterday's
    // (UTC) matches; evening kick-offs in the Americas cross midnight UTC.
    final today = DateTime.now().toUtc();
    final (espn, tsdb, ok) = await _fetchAll([
      for (final l in leagues) ...[
        if (l.onEspn) (l, false, '$_base/${l.slug}/scoreboard'),
        if (l.tsdb != null)
          for (final d in [today.subtract(const Duration(days: 1)), today])
            (l, true, '$_tsdb/eventsday.php?d=${_isoDay(d)}&l=${l.tsdb}'),
      ],
    ]);
    if (!ok) {
      throw const FixturesException("Couldn't load live matches. Check your connection and try again.");
    }
    final results = [mergeSportsDb(espn, tsdb)];
    final seen = <String>{};
    final list = [
      for (final m in results.expand((r) => r))
        if (m.state == MatchState.live && seen.add(m.id)) m,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _live = (DateTime.now(), list);
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
      final res = await _client
          .get(Uri.parse('$_base/${m.league.slug}/summary?event=${m.id}'))
          .timeout(const Duration(seconds: 15));
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

class FixturesException implements Exception {
  const FixturesException(this.message);
  final String message;
  @override
  String toString() => message;
}
