import 'dart:convert';

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

  test('fetches every league for the day either side, keeps the local day, dedupes and sorts', () async {
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
    expect(urls, hasLength(eng.leagues.length * 3));
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

  test('live matches come from every league, live only, A to Z', () async {
    final api = FixturesApi(
      client: MockClient((req) async {
        final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
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

    expect(urls.where((u) => u.contains('thesportsdb')), hasLength(6));
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
}
