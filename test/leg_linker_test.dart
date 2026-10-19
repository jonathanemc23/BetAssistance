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
}
