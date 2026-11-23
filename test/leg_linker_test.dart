import 'dart:convert';
import 'dart:io';

import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:bank_track/logic/leg_linker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final board = File('test/data/espn_scoreboard_draftkings.json').readAsStringSync();
  final requests = <Uri>[];
  final api = FixturesApi(
    client: MockClient((req) async {
      requests.add(req.url);
      // Only the Premier League has a match in the window.
      if (req.url.path.contains('/eng.1/scoreboard')) return http.Response(board, 200);
      if (req.url.host.contains('thesportsdb')) return http.Response('{"events":null}', 200);
      return http.Response('{"events":[]}', 200);
    }),
  );

  test('splits the usual ways a slip writes a fixture', () {
    expect(splitEvent('AC Fiorentina vs Como 1907'), ('AC Fiorentina', 'Como 1907'));
    expect(splitEvent('Millonarios - Santa Fe'), ('Millonarios', 'Santa Fe'));
    expect(splitEvent('Flamengo x Palmeiras'), ('Flamengo', 'Palmeiras'));
    expect(splitEvent('Everton v Chelsea'), ('Everton', 'Chelsea'));
    expect(splitEvent('Ambos marcan'), isNull);
  });

  test('typed and scanned picks are tied to the real match', () async {
    final legs = await linkLegs(api, const [
      ParlayLeg(selection: 'Chelsea', event: 'Everton FC vs Chelsea', odds: 2.2),
      ParlayLeg(selection: 'Empate · Resultado final', event: 'Chelsea - Everton', odds: 3.5),
      ParlayLeg(selection: 'Sí · Ambos equipos marcan', event: 'Everton v Chelsea', odds: 1.8),
      ParlayLeg(selection: 'Millonarios to win', event: 'Millonarios vs Nacional', odds: 2.0),
    ]);
    // ESPN takes one day per request (a range is rejected); the found day
    // is reused, and a pick that isn't found searches the next few days.
    final days = requests.where((u) => u.path.contains('/eng.1/scoreboard')).map((u) => u.queryParameters['dates']);
    expect(days, everyElement(matches(r'^\d{8}$')));
    expect(days.toSet().length, days.length);
    expect(days.length, 6); // Millonarios vs Nacional isn't anywhere

    final m = legs.first;
    expect((m.isLinked, m.matchId, m.leagueSlug, m.event), (true, '401878771', 'eng.1', 'Everton vs Chelsea'));
    expect(m.selection, 'Chelsea to win');
    expect(legs[1].selection, 'Draw');
    expect(legs[2].selection, 'Sí · Ambos equipos marcan'); // other markets keep their words
    expect(legs[2].isLinked, isTrue);
    expect(legs[3].isLinked, isFalse); // not in the fixtures
    expect(legs[3].odds, 2.0);
  });

  test('no connection leaves the picks as they were', () async {
    final down = FixturesApi(client: MockClient((_) async => throw const SocketException('down')));
    const leg = ParlayLeg(selection: 'Chelsea', event: 'Everton vs Chelsea', odds: 2.2);
    expect((await linkLegs(down, const [leg])).single.isLinked, isFalse);
  });

  fuzzyTests();
}

/// An ESPN scoreboard with [games] (id, kick-off UTC, home, away), each
/// served only on its own UTC day.
MockClient _boardClient(List<(String, String, String, String)> games) {
  final base = jsonDecode(File('test/data/espn_scoreboard_draftkings.json').readAsStringSync()) as Map<String, dynamic>;
  final template = jsonEncode((base['events'] as List).single);
  Map<String, dynamic> game((String, String, String, String) g) {
    final e = jsonDecode(template) as Map<String, dynamic>;
    final (id, date, home, away) = g;
    e['id'] = id;
    e['date'] = date;
    final c = (e['competitions'] as List).single as Map<String, dynamic>;
    c['id'] = id;
    c['date'] = date;
    for (final t in c['competitors'] as List) {
      final team = t['team'] as Map<String, dynamic>;
      final name = t['homeAway'] == 'home' ? home : away;
      for (final k in ['displayName', 'shortDisplayName', 'name', 'location']) {
        team[k] = name;
      }
      team['id'] = '${name.hashCode}';
    }
    return e;
  }

  return MockClient((req) async {
    if (req.url.host.contains('thesportsdb')) return http.Response('{"events":null}', 200);
    if (!req.url.path.contains('/eng.1/scoreboard')) return http.Response('{"events":[]}', 200);
    final day = req.url.queryParameters["dates"];

    final events = [
      for (final g in games)
        if (g.$2.substring(0, 10).replaceAll('-', '') == day) game(g),
    ];
    // As bytes: a String body would go out as Latin-1 and "León" would break.
    return http.Response.bytes(utf8.encode(jsonEncode({...base, 'events': events})), 200);
  });
}

void fuzzyTests() {
  test('team names written short or misread still count as the same club', () {
    expect(teamScore('Man Utd', 'Manchester United'), greaterThanOrEqualTo(0.8));
    expect(teamScore('Atl. Madrid', 'Atlético Madrid'), greaterThanOrEqualTo(0.8));
    expect(teamScore('Chelsae', 'Chelsea'), greaterThanOrEqualTo(0.8));
    expect(teamScore('Club León', 'León'), 1);
    expect(teamScore('Real Madrid', 'Real Betis'), lessThan(0.55));
    expect(teamScore('Leeds United', 'Manchester United'), lessThan(0.55));
  });

  final now = DateTime(2026, 11, 23, 12);

  test('short and misread names are linked to the match', () async {
    final api = FixturesApi(client: _boardClient([('1', '2026-11-23T15:00Z', 'Manchester United', 'Chelsea')]));
    final links = await findLinks(api, const [ParlayLeg(selection: 'Man Utd', event: 'Man Utd vs Chelsae', odds: 2.1)], now: now);
    expect(links.single.leg.isLinked, isTrue);
    expect(links.single.leg.matchId, '1');
    expect(links.single.leg.selection, 'Manchester United to win');
  });

  test('when several matches fit, the user is asked and nothing is linked on its own', () async {
    final api = FixturesApi(client: _boardClient([
      ('1', '2026-11-23T15:00Z', 'Manchester United', 'Arsenal'),
      ('2', '2026-11-23T17:30Z', 'Manchester City', 'Arsenal'),
    ]));
    const leg = ParlayLeg(selection: 'Arsenal', event: 'Manchester vs Arsenal', odds: 2.4);
    final link = (await findLinks(api, const [leg], now: now)).single;
    expect(link.needsPick, isTrue);
    expect(link.candidates.map((c) => c.match.id).toSet(), {'1', '2'});
    expect((await linkLegs(api, const [leg])).single.isLinked, isFalse);
  });

  test('the date on the slip finds older matches and picks the right meeting', () async {
    final api = FixturesApi(client: _boardClient([
      ('10', '2026-11-01T20:10Z', 'Cruz Azul', 'León'),
      ('11', '2026-11-24T20:10Z', 'Cruz Azul', 'León'),
    ]));
    const leg = ParlayLeg(selection: 'Cruz Azul', event: 'Cruz Azul vs Club León', odds: 1.7);
    final dated = (await findLinks(api, const [leg], dates: [DateTime(2026, 11, 1, 20, 10)], now: now)).single;
    expect(dated.leg.matchId, '10');
    final undated = (await findLinks(api, const [leg], now: now)).single;
    expect(undated.leg.matchId, '11');
  });

  test('a pick naming only one team offers that team\'s match to choose', () async {
    final api = FixturesApi(client: _boardClient([('1', '2026-11-24T15:00Z', 'Everton', 'Chelsea')]));
    final link = (await findLinks(api, const [ParlayLeg(selection: 'Chelsea to win', odds: 1.9)], now: now)).single;
    expect(link.needsPick, isTrue);
    expect(link.candidates.single.match.id, '1');
  });
}
