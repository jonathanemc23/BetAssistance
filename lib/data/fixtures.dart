import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Football fixtures from ESPN's public scoreboard feed
/// (site.api.espn.com, free and keyless). One request per league and day.
class League {
  const League(this.slug, this.name);
  final String slug;
  final String name;
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
  Country('arg', 'Argentina', '🇦🇷', [League('arg.1', 'Liga Profesional'), League('arg.copa', 'Copa Argentina')]),
  Country('aus', 'Australia', '🇦🇺', [League('aus.1', 'A-League')]),
  Country('bel', 'Belgium', '🇧🇪', [League('bel.1', 'Pro League')]),
  Country('bra', 'Brazil', '🇧🇷', [League('bra.1', 'Série A'), League('bra.2', 'Série B'), League('bra.copa_do_brazil', 'Copa do Brasil')]),
  Country('chi', 'Chile', '🇨🇱', [League('chi.1', 'Primera División')]),
  Country('col', 'Colombia', '🇨🇴', [League('col.1', 'Primera A'), League('col.2', 'Primera B')]),
  Country('ecu', 'Ecuador', '🇪🇨', [League('ecu.1', 'LigaPro')]),
  Country('eng', 'England', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', [
    League('eng.1', 'Premier League'),
    League('eng.2', 'Championship'),
    League('eng.3', 'League One'),
    League('eng.fa', 'FA Cup'),
    League('eng.league_cup', 'EFL Cup'),
  ]),
  Country('fra', 'France', '🇫🇷', [League('fra.1', 'Ligue 1'), League('fra.2', 'Ligue 2'), League('fra.coupe_de_france', 'Coupe de France')]),
  Country('ger', 'Germany', '🇩🇪', [League('ger.1', 'Bundesliga'), League('ger.2', '2. Bundesliga'), League('ger.dfb_pokal', 'DFB-Pokal')]),
  Country('ita', 'Italy', '🇮🇹', [League('ita.1', 'Serie A'), League('ita.2', 'Serie B'), League('ita.coppa_italia', 'Coppa Italia')]),
  Country('jpn', 'Japan', '🇯🇵', [League('jpn.1', 'J1 League')]),
  Country('mex', 'Mexico', '🇲🇽', [League('mex.1', 'Liga MX'), League('mex.2', 'Liga de Expansión')]),
  Country('ned', 'Netherlands', '🇳🇱', [League('ned.1', 'Eredivisie')]),
  Country('par', 'Paraguay', '🇵🇾', [League('par.1', 'Primera División')]),
  Country('per', 'Peru', '🇵🇪', [League('per.1', 'Liga 1')]),
  Country('por', 'Portugal', '🇵🇹', [League('por.1', 'Primeira Liga')]),
  Country('ksa', 'Saudi Arabia', '🇸🇦', [League('ksa.1', 'Pro League')]),
  Country('sco', 'Scotland', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', [League('sco.1', 'Premiership')]),
  Country('esp', 'Spain', '🇪🇸', [League('esp.1', 'LaLiga'), League('esp.2', 'LaLiga 2'), League('esp.copa_del_rey', 'Copa del Rey')]),
  Country('tur', 'Turkey', '🇹🇷', [League('tur.1', 'Süper Lig')]),
  Country('usa', 'United States', '🇺🇸', [League('usa.1', 'MLS'), League('usa.nwsl', 'NWSL')]),
  Country('uru', 'Uruguay', '🇺🇾', [League('uru.1', 'Primera División')]),
];

Country? countryByCode(String? code) {
  for (final c in countries) {
    if (c.code == code) return c;
  }
  return null;
}

/// Starting country from the phone's region (ISO 3166 alpha-2), else England.
Country defaultCountry(String? region) {
  const iso = {
    'AR': 'arg', 'AU': 'aus', 'BE': 'bel', 'BR': 'bra', 'CL': 'chi', 'CO': 'col', 'EC': 'ecu', 'GB': 'eng',
    'FR': 'fra', 'DE': 'ger', 'IT': 'ita', 'JP': 'jpn', 'MX': 'mex', 'NL': 'ned', 'PY': 'par', 'PE': 'per',
    'PT': 'por', 'SA': 'ksa', 'ES': 'esp', 'TR': 'tur', 'US': 'usa', 'UY': 'uru',
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
  });
  final String id;
  final League league;
  final DateTime kickoff; // UTC
  final Team home;
  final Team away;
  final MatchState state;
  final String detail; // "FT", "67'", "Postponed"...
  final String? venue;

  String get title => '${home.name} vs ${away.name}';
  bool get hasScore => state == MatchState.live || state == MatchState.finished;

  /// A pending single bet on this match, for the bet form.
  Bet toBetTemplate() => Bet(
        selection: '',
        event: title,
        sport: 'Soccer',
        date: isoDate(kickoff.toLocal()),
        stake: 0,
        odds: 0,
        created: DateTime.now().toIso8601String(),
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
      out.add(Match(
        id: e['id'].toString(),
        league: league,
        kickoff: DateTime.parse(e['date'] as String).toUtc(),
        home: team(side('home')),
        away: team(side('away')),
        state: state,
        detail: (type['shortDetail'] ?? type['detail'] ?? '') as String,
        venue: comp['venue']?['fullName'] as String?,
      ));
    } catch (_) {
      // Skip events we can't read rather than failing the whole day.
    }
  }
  return out;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

class FixturesApi {
  FixturesApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _cache = <String, (DateTime, List<Match>)>{};

  static const _base = 'https://site.api.espn.com/apis/site/v2/sports/soccer';

  /// Matches kicking off on [day] in the phone's time zone, grouped feed-wide.
  /// ESPN buckets matches by US Eastern date, so the day before and after are
  /// fetched too and filtered locally. Throws only if every request failed.
  Future<List<Match>> matches(Country country, DateTime day, {bool refresh = false}) async {
    final local = DateTime(day.year, day.month, day.day);
    final key = '${country.code}-${_ymd(local)}';
    final hit = _cache[key];
    if (!refresh && hit != null && DateTime.now().difference(hit.$1) < const Duration(minutes: 2)) return hit.$2;

    final days = [local.subtract(const Duration(days: 1)), local, local.add(const Duration(days: 1))];
    var failures = 0, requests = 0;
    final results = await Future.wait([
      for (final l in country.leagues)
        for (final d in days)
          () async {
            requests++;
            try {
              final res = await _client
                  .get(Uri.parse('$_base/${l.slug}/scoreboard?dates=${_ymd(d)}'))
                  .timeout(const Duration(seconds: 15));
              if (res.statusCode != 200) {
                failures++;
                return const <Match>[];
              }
              return parseScoreboard(utf8.decode(res.bodyBytes), l);
            } catch (_) {
              failures++;
              return const <Match>[];
            }
          }(),
    ]);
    if (requests > 0 && failures == requests) {
      throw const FixturesException("Couldn't load matches. Check your connection and try again.");
    }
    final seen = <String>{};
    final list = [
      for (final m in results.expand((r) => r))
        if (seen.add(m.id) && _sameDay(m.kickoff.toLocal(), local)) m,
    ]..sort((a, b) {
        final c = a.kickoff.compareTo(b.kickoff);
        return c != 0 ? c : a.home.name.compareTo(b.home.name);
      });
    _cache[key] = (DateTime.now(), list);
    return list;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class FixturesException implements Exception {
  const FixturesException(this.message);
  final String message;
  @override
  String toString() => message;
}
