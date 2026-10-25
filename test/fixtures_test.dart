import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal ESPN scoreboard event, same shape as the live feed.
Map<String, Object?> espnEvent(
  String id,
  String date,
  String home,
  String away, {
  String state = 'pre',
  bool completed = false,
  String detail = 'Scheduled',
  String hs = '0',
  String as = '0',
  List<double>? odds,
}) => {
  'id': id,
  'date': date,
  'name': '$away at $home',
  'status': {
    'type': {'state': state, 'completed': completed, 'shortDetail': detail, 'detail': detail},
  },
  'competitions': [
    {
      'venue': {'fullName': '$home Stadium'},
      'odds': odds == null
          ? [null]
          : [
              {
                'provider': {'id': '2000', 'name': 'Bet 365', 'displayName': 'Bet 365'},
                'homeTeamOdds': {'summary': '', 'value': odds[0]},
                'drawOdds': {'summary': '', 'value': odds[1]},
                'awayTeamOdds': {'summary': '', 'value': odds[2]},
              },
            ],
      'competitors': [
        {
          'homeAway': 'home',
          'score': hs,
          'team': {'displayName': home, 'shortDisplayName': home, 'logo': 'https://x/$id-h.png'},
        },
        {
          'homeAway': 'away',
          'score': as,
          'team': {'displayName': away, 'shortDisplayName': away, 'logo': 'https://x/$id-a.png'},
        },
      ],
    },
  ],
};

String board(List<Map<String, Object?>> events) => jsonEncode({'leagues': [], 'events': events});

/// [event] as ESPN's all-leagues scoreboard lists it: tagged with the
/// league's numeric id (eng.1 is 700, esp.1 740) in its uid.
Map<String, Object?> inLeague(String leagueId, Map<String, Object?> event) => {
  ...event,
  'uid': 's:600~l:$leagueId~e:${event['id']}',
};

void main() {
  const pl = League('eng.1', 'Premier League');

  test('parses teams, scores, state and venue', () {
    final list = parseScoreboard(
      board([
        espnEvent('1', '2026-10-18T13:00Z', 'AFC Bournemouth', 'Sunderland'),
        espnEvent('2', '2026-10-18T15:30Z', 'Arsenal', 'Chelsea', state: 'in', detail: "67'", hs: '2', as: '1'),
        espnEvent(
          '3',
          '2026-10-18T11:00Z',
          'Leeds',
          'Everton',
          state: 'post',
          completed: true,
          detail: 'FT',
          hs: '0',
          as: '3',
        ),
        {'id': 'broken'},
      ]),
      pl,
    );
    expect(list, hasLength(3));
    expect(list[0].home.name, 'AFC Bournemouth');
    expect(list[0].away.name, 'Sunderland');
    expect(list[0].state, MatchState.scheduled);
    expect(list[0].kickoff, DateTime.utc(2026, 10, 18, 13));
    expect(list[0].venue, 'AFC Bournemouth Stadium');
    expect(list[1].state, MatchState.live);
    expect(list[1].home.score, '2');
    expect(list[2].state, MatchState.finished);
    expect(list[2].title, 'Leeds vs Everton');
    final bet = list[2].toBetTemplate();
    expect(bet.event, 'Leeds vs Everton');
    expect(bet.sport, 'Soccer');
    expect(list[0].odds, isNull); // ESPN sends [null] when it has no prices
  });

  test('reads 1X2 odds, decimal or American moneyline', () {
    final list = parseScoreboard(
      board([
        espnEvent('1', '2026-10-17T19:00Z', 'Everton', 'Chelsea', odds: [3.1, 3.5, 2.15]),
        {
          ...espnEvent('2', '2026-10-17T23:00Z', 'Austin FC', 'LA Galaxy'),
          'competitions': [
            {
              ...(espnEvent('2', '2026-10-17T23:00Z', 'Austin FC', 'LA Galaxy')['competitions'] as List).first
                  as Map<String, Object?>,
              'odds': [
                {
                  'provider': {'name': 'DraftKings'},
                  'homeTeamOdds': {'moneyLine': 150},
                  'awayTeamOdds': {'moneyLine': -200},
                },
              ],
            },
          ],
        },
      ]),
      pl,
    );
    final o = list[0].odds!;
    expect([o.home, o.draw, o.away], [3.1, 3.5, 2.15]);
    expect(o.provider, 'Bet 365');
    final us = list[1].odds!;
    expect(us.home, closeTo(2.5, 1e-9));
    expect(us.draw, isNull);
    expect(us.away, closeTo(1.5, 1e-9));
    final bet = list[0].toBetTemplate(selection: 'Everton to win', odds: o.home!);
    expect(bet.selection, 'Everton to win');
    expect(bet.odds, 3.1);
  });

  test('fetches every league for the dates the local day overlaps, keeps the local day, dedupes and sorts', () async {
    final urls = <String>[];
    final client = MockClient((req) async {
      urls.add(req.url.toString());
      if (req.url.path.contains('eng.1') && req.url.queryParameters['dates'] == '20261018') {
        return http.Response(
          board([
            espnEvent('a', '2026-10-18T16:00Z', 'Arsenal', 'Chelsea'),
            espnEvent('b', '2026-10-18T12:00Z', 'Leeds', 'Everton'),
          ]),
          200,
        );
      }
      if (req.url.path.contains('eng.1') && req.url.queryParameters['dates'] == '20261019') {
        // Same match listed again, plus one on the next day.
        return http.Response(
          board([
            espnEvent('a', '2026-10-18T16:00Z', 'Arsenal', 'Chelsea'),
            espnEvent('c', '2026-10-20T19:00Z', 'Spurs', 'Fulham'),
          ]),
          200,
        );
      }
      if (req.url.path.contains('eng.fa')) return http.Response('not found', 404);
      return http.Response(board([]), 200);
    });
    final eng = countryByCode('eng')!;
    final list = await FixturesApi(client: client).matches(eng, DateTime(2026, 10, 18));
    // ESPN files by US Eastern date: one or two dates per local day.
    final dates = espnDatesFor(DateTime(2026, 10, 18));
    expect(dates.length, inInclusiveRange(1, 2));
    expect(urls, hasLength(eng.leagues.length * dates.length));
    expect(list.map((m) => m.id), ['b', 'a']);
  });

  test('reports an error only when every request fails', () async {
    final client = MockClient((_) async => throw Exception('offline'));
    expect(
      FixturesApi(client: client).matches(countryByCode('col')!, DateTime(2026, 10, 18)),
      throwsA(isA<FixturesException>()),
    );
  });

  test('default country follows the phone region', () {
    expect(defaultCountry('CO').name, 'Colombia');
    expect(defaultCountry('es').name, 'Spain');
    expect(defaultCountry('ZZ').name, 'England');
    expect(defaultCountry(null).name, 'England');
  });

  test('live football comes from ESPN in one request, live only, A to Z', () async {
    final urls = <Uri>[];
    final api = FixturesApi(
      client: MockClient((req) async {
        urls.add(req.url);
        if (req.url.path.endsWith('/soccer/all/scoreboard')) {
          return http.Response(
            board([
              inLeague('700', espnEvent('1', '2026-10-18T14:00Z', 'Chelsea', 'Fulham', state: 'in', detail: "30'")),
              inLeague('700', espnEvent('2', '2026-10-18T17:00Z', 'Arsenal', 'Spurs')),
              inLeague('740', espnEvent('3', '2026-10-18T14:00Z', 'Barcelona', 'Girona', state: 'in', detail: "10'")),
              // A league the app doesn't list.
              inLeague('99999', espnEvent('4', '2026-10-18T14:00Z', 'Nowhere', 'Elsewhere', state: 'in')),
            ]),
            200,
          );
        }
        return http.Response(board([]), 200);
      }),
    );
    final live = await api.liveMatches();
    expect(live.map((m) => m.title), ['Barcelona vs Girona', 'Chelsea vs Fulham']);
    expect(live.first.league.slug, 'esp.1');
    expect(urls.where((u) => u.host.contains('espn')), hasLength(1));
  });

  test('live matches come from every league when the all-leagues board is down', () async {
    final api = FixturesApi(
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
        if (slug == 'all') return http.Response('', 503);
        if (req.url.queryParameters.containsKey('dates')) return http.Response(board([]), 200);
        return switch (slug) {
          'eng.1' => http.Response(
              board([
                espnEvent('1', '2026-10-18T14:00Z', 'Chelsea', 'Fulham', state: 'in', detail: "30'", hs: '0', as: '0'),
                espnEvent('2', '2026-10-18T17:00Z', 'Arsenal', 'Spurs'),
              ]),
              200),
          'esp.1' => http.Response(
              board([espnEvent('3', '2026-10-18T14:00Z', 'Barcelona', 'Girona', state: 'in', detail: "10'", hs: '1', as: '0')]),
              200),
          _ => http.Response(board([]), 200),
        };
      }),
    );
    final live = await api.liveMatches();
    expect(live.map((m) => m.title), ['Barcelona vs Girona', 'Chelsea vs Fulham']);
    expect(live.first.league.slug, 'esp.1');
  });

  Map<String, Object?> tsdbEvent(String id, String ts, String home, String away,
          {String status = 'NS', String? hs, String? as}) =>
      {
        'idEvent': id,
        'strTimestamp': ts,
        'dateEvent': ts.substring(0, 10),
        'strTime': ts.substring(11),
        'strHomeTeam': home,
        'strAwayTeam': away,
        'intHomeScore': hs,
        'intAwayScore': as,
        'strStatus': status,
        'strHomeTeamBadge': 'https://r2/$id-h.png',
        'strAwayTeamBadge': null,
        'strVenue': '',
      };

  test('reads TheSportsDB events as UTC with their status and score', () {
    const cup = League('tsdb.5831', 'Belgian Cup', tsdb: 5831);
    final list = parseSportsDb(
      jsonEncode({
        'events': [
          tsdbEvent('1', '2026-10-18T11:30:00', 'Mechelen', 'Eupen', status: '2H', hs: '5', as: '1'),
          tsdbEvent('2', '2026-10-18T16:00:00', 'Beerschot', 'Anderlecht'),
          tsdbEvent('3', '2026-10-12T20:00:00', 'Universidad de Chile', 'Ñublense', status: 'FT', hs: '6', as: '0'),
          tsdbEvent('4', '2026-10-19T18:00:00', 'Genk', 'Gent', status: 'PST'),
        ],
      }),
      cup,
    );
    expect(list.map((m) => m.id), ['tsdb:1', 'tsdb:2', 'tsdb:3', 'tsdb:4']);
    expect(list[0].kickoff, DateTime.utc(2026, 10, 18, 11, 30));
    expect((list[0].state, list[0].detail, list[0].home.score, list[0].away.score),
        (MatchState.live, '2nd half', '5', '1'));
    expect(list[0].home.logo, 'https://r2/1-h.png');
    expect(list[0].away.logo, isNull);
    expect(list[0].venue, isNull);
    expect((list[1].state, list[1].home.score), (MatchState.scheduled, null));
    expect(list[2].state, MatchState.finished);
    expect((list[3].state, list[3].detail), (MatchState.other, 'Postponed'));
    expect(parseSportsDb('{"events":null}', cup), isEmpty);
  });

  test('team names match across feeds', () {
    expect(sameTeam('Ñublense', 'Nublense'), isTrue);
    expect(sameTeam('Deportes Limache', 'Limache'), isTrue);
    expect(sameTeam('Unión La Calera', 'Union La Calera'), isTrue);
    expect(sameTeam('Universidad de Chile', 'Universidad Católica'), isFalse);
    expect(sameTeam('Colo Colo', 'Coquimbo Unido'), isFalse);
  });

  test('Chile: TheSportsDB scores update stale ESPN matches, and add the ones ESPN lacks', () async {
    final urls = <String>[];
    final api = FixturesApi(
      client: MockClient((req) async {
        urls.add(req.url.toString());
        final u = req.url;
        if (u.host.contains('espn') && u.path.contains('chi.1') && u.queryParameters['dates'] == '20261012') {
          // ESPN still shows the match as not started after it was played.
          return http.Response.bytes(
              utf8.encode(board([
                espnEvent('401', '2026-10-12T20:00Z', 'Universidad de Chile', 'Ñublense', odds: [1.5, 4.0, 6.0]),
              ])),
              200);
        }
        if (u.host.contains('thesportsdb') && u.queryParameters['l'] == '4627' && u.queryParameters['d'] == '2026-10-12') {
          return http.Response(
              jsonEncode({
                'events': [
                  tsdbEvent('9', '2026-10-12T20:00:00', 'Universidad de Chile', 'Nublense', status: 'FT', hs: '6', as: '0'),
                  tsdbEvent('10', '2026-10-12T23:00:00', 'Palestino', 'Limache', status: 'FT', hs: '1', as: '1'),
                ],
              }),
              200);
        }
        return http.Response(board([]), 200);
      }),
    );
    final chile = countryByCode('chi')!;
    final list = await api.matches(chile, DateTime(2026, 10, 12));

    // No rounds to read (the mock has none): the day lists instead.
    expect(urls.where((u) => u.contains('eventsday')), hasLength(2 * sportsDbDatesFor(DateTime(2026, 10, 12)).length));
    expect(list.map((m) => m.id), ['401', 'tsdb:10']);
    final u = list.first;
    expect((u.state, u.home.score, u.away.score, u.odds?.home), (MatchState.finished, '6', '0', 1.5));

    // A TheSportsDB-only match opens with its status and score, without ESPN.
    final d = await api.details(list.last);
    expect((d.state, d.homeScore, d.awayScore), (MatchState.finished, 1, 1));
  });

  test('Belgian cup matches come from TheSportsDB only', () async {
    final api = FixturesApi(
      client: MockClient((req) async {
        final u = req.url;
        if (u.host.contains('espn')) {
          expect(u.path, isNot(contains('tsdb')));
          return http.Response(board([]), 200);
        }
        if (u.queryParameters['l'] == '5831' && u.queryParameters['d'] == '2026-10-18') {
          return http.Response(jsonEncode({'events': [tsdbEvent('7', '2026-10-18T16:00:00', 'Beerschot', 'Anderlecht')]}), 200);
        }
        return http.Response(jsonEncode({'events': null}), 200);
      }),
    );
    final list = await api.matches(countryByCode('bel')!, DateTime(2026, 10, 18));
    expect(list.single.title, 'Beerschot vs Anderlecht');
    expect(list.single.league.name, 'Belgian Cup');
  });

  test('a full TheSportsDB day list (it stops at three) reads the whole rounds', () async {
    final urls = <Uri>[];
    final round9 = [
      for (var i = 0; i < 5; i++) tsdbEvent('9$i', '2026-10-18T1$i:00:00', 'Home $i', 'Away $i'),
      tsdbEvent('99', '2026-10-16T18:00:00', 'Dynamo Kyiv', 'Shakhtar', status: 'FT', hs: '1', as: '2'),
    ];
    final api = FixturesApi(
      client: MockClient((req) async {
        urls.add(req.url);
        final u = req.url;
        if (u.host.contains('espn')) return http.Response(board([]), 200);
        if (u.path.endsWith('eventspastleague.php')) {
          return http.Response(jsonEncode({'events': [round9.last..['intRound'] = '9'..['strSeason'] = '2026-2027']}), 200);
        }
        if (u.path.endsWith('eventsnextleague.php')) {
          return http.Response(
              jsonEncode({
                'events': [
                  {...tsdbEvent('101', '2026-10-24T15:00:00', 'Home 1', 'Away 2'), 'intRound': '10', 'strSeason': '2026-2027'},
                ],
              }),
              200);
        }
        if (u.path.endsWith('eventsround.php')) {
          expect((u.queryParameters['id'], u.queryParameters['s']), ('4354', '2026-2027'));
          return http.Response(
              jsonEncode({
                'events': u.queryParameters['r'] == '9'
                    ? round9
                    : [tsdbEvent('101', '2026-10-24T15:00:00', 'Home 1', 'Away 2')],
              }),
              200);
        }
        // The day list: three at most.
        final d = u.queryParameters['d'];
        return http.Response(jsonEncode({'events': round9.where((e) => e['dateEvent'] == d).take(3).toList()}), 200);
      }),
    );
    final ukraine = countryByCode('ukr')!;
    final day = await api.matches(ukraine, DateTime(2026, 10, 18, 12).toUtc().toLocal());
    expect(day.where((m) => _isOn(m, 2026, 10, 18)), hasLength(5));
    expect(urls.where((u) => u.path.endsWith('eventsround.php')), hasLength(2));

    // A quiet day's list is complete: no rounds are read for it.
    final before = urls.length;
    expect(await api.matches(ukraine, DateTime(2026, 10, 30, 12).toUtc().toLocal()), isEmpty);
    expect(urls.skip(before).map((u) => u.path.split('/').last), everyElement('eventsday.php'));
  });

  test('a dropped connection is tried once more', () async {
    var calls = 0;
    final api = FixturesApi(
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        if (req.url.path.contains('/eng.1/')) {
          if (calls++ == 0) throw const SocketException('Connection closed before full header was received');
          return http.Response(board([espnEvent('a', '2026-10-18T14:00Z', 'Arsenal', 'Chelsea')]), 200);
        }
        return http.Response(board([]), 200);
      }),
    );
    final list = await api.matches(countryByCode('eng')!, DateTime(2026, 10, 18));
    expect(list.map((m) => m.id), ['a']);
  });

  test('live refreshes read only the leagues with a match on', () async {
    final now = DateTime.now().toUtc();
    String at(Duration d) => '${now.add(d).toIso8601String().substring(0, 16)}Z';
    final urls = <Uri>[];
    final api = FixturesApi(
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
        // Without the all-leagues board, leagues are read one by one.
        if (slug == 'all') return http.Response('', 503);
        urls.add(req.url);
        return switch (slug) {
          'eng.1' => http.Response(
              board([espnEvent('1', at(const Duration(minutes: -30)), 'Chelsea', 'Fulham', state: 'in', detail: "30'")]),
              200),
          'esp.1' => http.Response(board([espnEvent('2', at(const Duration(minutes: 5)), 'Barcelona', 'Girona')]), 200),
          'ita.1' => http.Response(board([espnEvent('3', at(const Duration(hours: 5)), 'Inter', 'Milan')]), 200),
          _ => http.Response(board([]), 200),
        };
      }),
    );
    expect((await api.liveMatches()).map((m) => m.title), ['Chelsea vs Fulham']);
    int espnCount() => urls.where((u) => u.host.contains('espn')).length;
    final full = espnCount();
    urls.clear();
    await api.liveMatches(refresh: true);
    final espn = {for (final u in urls.where((u) => u.host.contains('espn'))) u.pathSegments[u.pathSegments.length - 2]};
    expect(espn, {'eng.1', 'esp.1'});
    expect(urls.length, lessThan(full ~/ 4));
    urls.clear();
    await api.liveMatches(full: true);
    expect(espnCount(), full);
  });
  test('a live league that fails on a refresh keeps its matches', () async {
    final now = DateTime.now().toUtc();
    final kickoff = '${now.subtract(const Duration(minutes: 30)).toIso8601String().substring(0, 16)}Z';
    var down = false;
    final api = FixturesApi(
      retryDelay: Duration.zero,
      client: MockClient((req) async {
        if (req.url.path.contains('/all/')) return http.Response('', 503);
        if (req.url.path.contains('/eng.1/')) {
          if (down) throw const SocketException('reset');
          return http.Response(board([espnEvent('1', kickoff, 'Chelsea', 'Fulham', state: 'in', detail: "30'")]), 200);
        }
        if (req.url.path.contains('/esp.1/')) {
          return http.Response(board([espnEvent('2', kickoff, 'Barcelona', 'Girona', state: 'in', detail: "31'")]), 200);
        }
        return http.Response(board([]), 200);
      }),
    );
    expect((await api.liveMatches()).map((m) => m.title), ['Barcelona vs Girona', 'Chelsea vs Fulham']);
    down = true;
    expect((await api.liveMatches(refresh: true)).map((m) => m.title), ['Barcelona vs Girona', 'Chelsea vs Fulham']);
  });
  test("a women's league match from TheSportsDB is not folded into the men's ESPN match", () {
    const ligaMx = League('mex.1', 'Liga MX');
    const femenil = League('tsdb.5206', 'Liga MX Femenil', tsdb: 5206);
    final men = parseScoreboard(board([espnEvent('401', '2026-10-21T02:00Z', 'Guadalajara', 'Necaxa')]), ligaMx);
    final women = parseSportsDb(
      jsonEncode({'events': [tsdbEvent('9', '2026-10-20T23:00:00', 'CD Guadalajara Femenil', 'Necaxa Femenil')]}),
      femenil,
    );
    expect(mergeSportsDb(men, women).map((m) => m.id), ['401', 'tsdb:9']);
  });

  test('basketball and baseball read their own ESPN feeds, apart from football', () async {
    final paths = <String>[];
    final api = FixturesApi(
      client: MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path.contains('/basketball/nba/')) {
          return http.Response(
            board([
              espnEvent('n1', '2026-10-20T23:30Z', 'Boston Celtics', 'New York Knicks', state: 'in', detail: 'Q3 4:12'),
            ]),
            200,
          );
        }
        return http.Response(board([]), 200);
      }),
    );
    final usa = countryByCode('usa')!;
    final list = await api.matches(usa, DateTime(2026, 10, 20), sport: Sport.basketball);
    expect(paths, isNotEmpty);
    expect(paths.every((p) => p.contains('/sports/basketball/')), isTrue);
    expect(list.single.league.slug, 'nba');
    expect(list.single.toBetTemplate().sport, 'Basketball');

    paths.clear();
    final live = await api.liveMatches(sport: Sport.basketball);
    expect(live.map((m) => m.title), ['Boston Celtics vs New York Knicks']);
    expect(paths.where((p) => p.contains('/sports/soccer/')), isEmpty);
    expect(paths.where((p) => p.contains('/sports/baseball/')), isEmpty);
  });

  test('every sport has countries, and the new leagues are listed', () {
    for (final s in Sport.values) {
      expect(countries.where((c) => c.has(s)), isNotEmpty, reason: s.name);
    }
    expect(countryByCode('cro')!.leagues.map((l) => l.name), ['HNL', 'Prva NL']);
    expect(countryByCode('swe')!.leagues.map((l) => l.name), contains('Superettan'));
    expect(countryByCode('ger')!.leaguesIn(Sport.soccer).map((l) => l.name), contains('Frauen-Bundesliga'));
    expect(countryByCode('usa')!.leaguesIn(Sport.baseball).map((l) => l.name), contains('MLB'));
    // A league rebuilt from a saved slug still knows its sport.
    expect(const League('mlb', 'MLB').knownSport, Sport.baseball);
    final slugs = [
      for (final c in countries)
        for (final l in c.leagues) l.slug,
    ];
    expect(slugs.toSet().length, slugs.length, reason: 'league slugs are unique');
  });

  test('TheSportsDB quarters and innings read as live', () {
    expect(sportsDbStatus('Q2', hasScore: true), (MatchState.live, 'Q2'));
    expect(sportsDbStatus('OT', hasScore: true), (MatchState.live, 'OT'));
    expect(sportsDbStatus('IN7', hasScore: true), (MatchState.live, 'IN7'));
    expect(sportsDbStatus('AOT', hasScore: true), (MatchState.finished, 'AOT'));
  });
  test("a country's ESPN matches show before TheSportsDB's are in", () async {
    final tsdb = Completer<void>();
    final api = FixturesApi(
      client: MockClient((req) async {
        final u = req.url;
        if (u.host.contains('thesportsdb')) {
          await tsdb.future;
          if (u.queryParameters['d'] == '2026-10-18') {
            return http.Response(
              jsonEncode({
                'events': [tsdbEvent('7', '2026-10-18T15:00:00', 'Vasco', 'Remo', status: 'FT', hs: '2', as: '0')],
              }),
              200,
            );
          }
          return http.Response('{"events":null}', 200);
        }
        if (u.path.contains('/bra.1/') && u.queryParameters['dates'] == '20261018') {
          return http.Response(board([espnEvent('1', '2026-10-18T15:00Z', 'Flamengo', 'Santos')]), 200);
        }
        return http.Response(board([]), 200);
      }),
    );
    final partial = <List<String>>[];
    final full = api.matches(
      countryByCode('bra')!,
      DateTime(2026, 10, 18),
      onPartial: (ms) => partial.add([for (final m in ms) m.title]),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(partial, [
      ['Flamengo vs Santos'],
    ]);
    tsdb.complete();
    expect((await full).map((m) => m.title), ['Flamengo vs Santos', 'Vasco vs Remo']);
  });

  test('a starred match its day list leaves out is looked up on its own', () async {
    final api = FixturesApi(
      client: MockClient((req) async {
        final u = req.url;
        if (u.path.endsWith('lookupevent.php') && u.queryParameters['id'] == '55') {
          return http.Response(
            jsonEncode({
              'events': [
                tsdbEvent(
                  '55',
                  '2026-10-17T16:00:00',
                  'Apollon Limassol',
                  'Nea Salamis',
                  status: 'FT',
                  hs: '4',
                  as: '2',
                ),
              ],
            }),
            200,
          );
        }
        if (u.path.endsWith('/eng.1/summary')) {
          return http.Response(
            jsonEncode({
              'header': {
                'competitions': [
                  {
                    'status': {
                      'type': {'state': 'post', 'shortDetail': 'FT'},
                    },
                    'competitors': [
                      {
                        'homeAway': 'home',
                        'score': '2',
                        'team': {'id': '1'},
                      },
                      {
                        'homeAway': 'away',
                        'score': '1',
                        'team': {'id': '2'},
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }
        if (u.host.contains('thesportsdb')) return http.Response('{"events":null}', 200);
        return http.Response(board([]), 200);
      }),
    );
    Match saved(String id, League l, String home, String away) => Match(
      id: id,
      league: l,
      kickoff: DateTime.utc(2026, 10, 17, 16),
      home: Team(home, home, null, null),
      away: Team(away, away, null, null),
      state: MatchState.scheduled,
      detail: '',
    );
    final updates = <String>[];
    final found = await api.refreshMatches([
      saved('tsdb:55', leagueBySlug('tsdb.4630')!, 'Apollon Limassol', 'Nea Salamis'),
      saved('77', pl, 'Aston Villa', 'Man City'),
    ], onUpdate: (u) => updates.addAll(u.keys));
    expect(
      {for (final e in found.entries) e.key: (e.value.state, e.value.home.score, e.value.away.score)},
      {'tsdb:55': (MatchState.finished, '4', '2'), '77': (MatchState.finished, '2', '1')},
    );
    expect(updates.toSet(), {'tsdb:55', '77'});
  });

  test('a table from results: points, then goal difference, then goals', () {
    Match result(String home, String away, int hs, int as) => Match(
      id: '$home-$away',
      league: pl,
      kickoff: DateTime.utc(2026, 10, 1),
      home: Team(home, home, null, '$hs'),
      away: Team(away, away, null, '$as'),
      state: MatchState.finished,
      detail: 'FT',
    );
    final results = [result('A', 'B', 2, 0), result('C', 'A', 1, 1), result('B', 'C', 3, 0), result('D', 'A', 0, 0)];
    final table = tableFromResults(results);
    expect(
      [for (final r in table) '${r.rank} ${r.team} ${r.played} ${r.points} ${r.goalDiff}'],
      ['1 A 3 5 +2', '2 B 2 3 +1', '3 D 1 1 0', '4 C 2 1 -3'],
    );
    final a = teamFromResults('A', results);
    expect((a.form, a.record, a.lastGames.length), ('WDD', '1-2-0', 3));
  });

  test('a league whose current stage has no table yet shows the stage before (Ecuador)', () async {
    Map<String, Object?> entry(String id, String name, int rank, int pts) => {
      'team': {'id': id, 'displayName': name},
      'stats': [
        {'name': 'rank', 'displayValue': '$rank'},
        {'name': 'gamesPlayed', 'displayValue': '30'},
        {'name': 'points', 'displayValue': '$pts'},
      ],
    };
    final urls = <Uri>[];
    final api = FixturesApi(
      client: MockClient((req) async {
        final u = req.url;
        if (!u.path.endsWith('/ecu.1/standings')) return http.Response(board([]), 200);
        urls.add(u);
        final stage = u.queryParameters['seasontype'];
        return http.Response(
          jsonEncode({
            'children': stage == '1'
                ? [
                    {
                      'name': 'First Stage',
                      'standings': {
                        'entries': [entry('2', 'Emelec', 2, 50), entry('1', 'Independiente del Valle', 1, 74)],
                      },
                    },
                  ]
                : [],
            'seasons': [
              {
                'year': 2026,
                'types': [
                  {'id': '1', 'name': 'First Stage', 'hasStandings': true},
                  {'id': '2', 'name': 'Final Stage', 'hasStandings': true},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final m = Match(
      id: '401',
      league: leagueBySlug('ecu.1')!,
      kickoff: DateTime.utc(2026, 10, 25, 19),
      home: const Team('Emelec', 'Emelec', null, null),
      away: const Team('Guayaquil City FC', 'Guayaquil City', null, null),
      state: MatchState.scheduled,
      detail: '',
    );
    final d = await api.extras(
      m,
      const MatchDetails(
        home: TeamInfo(id: '2', name: 'Emelec'),
      ),
    );
    expect(d?.tableTitle, 'First Stage');
    expect([for (final r in d!.table) r.team], ['Independiente del Valle', 'Emelec']);
    expect([for (final u in urls) u.queryParameters['seasontype']], [null, '2', '1']);
  });

  test('a TheSportsDB match gets a table, form and meetings from its rounds (Cyprus)', () async {
    final api = FixturesApi(
      client: MockClient((req) async {
        final u = req.url;
        if (u.path.endsWith('eventspastleague.php')) {
          return http.Response(
            jsonEncode({
              'events': [
                {
                  ...tsdbEvent('3', '2026-10-10T16:00:00', 'AEL', 'Omonia', status: 'FT', hs: '1', as: '0'),
                  'intRound': '2',
                  'strSeason': '2026-2027',
                },
              ],
            }),
            200,
          );
        }
        if (u.path.endsWith('eventsround.php')) {
          return http.Response(
            jsonEncode({
              'events': u.queryParameters['r'] == '1'
                  ? [
                      tsdbEvent('1', '2026-10-03T16:00:00', 'AEL', 'Apollon', status: 'FT', hs: '2', as: '2'),
                      tsdbEvent('2', '2026-10-03T18:00:00', 'Omonia', 'Anorthosis', status: 'FT', hs: '3', as: '0'),
                    ]
                  : [
                      tsdbEvent('3', '2026-10-10T16:00:00', 'AEL', 'Omonia', status: 'FT', hs: '1', as: '0'),
                      tsdbEvent('4', '2026-10-10T18:00:00', 'Apollon', 'Anorthosis', status: 'FT', hs: '0', as: '1'),
                    ],
            }),
            200,
          );
        }
        return http.Response('{"events":null}', 200);
      }),
    );
    final m = Match(
      id: 'tsdb:9',
      league: leagueBySlug('tsdb.4630')!,
      kickoff: DateTime.utc(2026, 10, 17, 16),
      home: const Team('Omonia', 'Omonia', null, null),
      away: const Team('AEL', 'AEL', null, null),
      state: MatchState.scheduled,
      detail: '',
    );
    final d = (await api.extras(m, await api.details(m)))!;
    expect([for (final r in d.table) '${r.team} ${r.points}'], ['AEL 4', 'Omonia 3', 'Anorthosis 3', 'Apollon 1']);
    expect((d.home.form, d.away.form), ('LW', 'WD'));
    expect(d.h2h.map((g) => '${g.home} ${g.score} ${g.away}'), ['AEL 1-0 Omonia']);
  });
}

bool _isOn(Match m, int y, int mo, int d) => m.kickoff.year == y && m.kickoff.month == mo && m.kickoff.day == d;
