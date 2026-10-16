import 'dart:io';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bank_track/data/fixtures.dart';

import 'fixtures_test.dart' show espnEvent, board;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Loads real Roboto and Material Icons so screenshots are readable.
Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/flutter'}/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async => ByteData.view(Uint8List.fromList(File('$dir/$n').readAsBytesSync()).buffer);
  final roboto = FontLoader('Roboto');
  for (final n in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'))).load();
}

Future<BankStore> seededStore() async {
  final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
  await db.saveSettings(const Settings(startBankroll: 1000, startDate: '2026-07-18', unit: 20));
  final rows = <(String, String, String, String, double, double, BetStatus, double?)>[
    ('2026-07-20', 'Soccer', 'Liverpool vs Brentford', 'Liverpool -1.5', 20, 2.05, BetStatus.won, null),
    ('2026-07-24', 'Basketball', 'Celtics vs Knicks', 'Celtics -4.5', 20, 1.91, BetStatus.lost, null),
    ('2026-07-29', 'Tennis', 'Sinner vs Rune', 'Sinner to win', 30, 1.45, BetStatus.won, null),
    ('2026-08-04', 'Soccer', 'Real Madrid vs Sevilla', 'Over 2.5 goals', 20, 1.80, BetStatus.won, null),
    ('2026-08-09', 'MMA', 'UFC main event', 'Underdog by KO', 10, 3.40, BetStatus.lost, null),
    ('2026-08-16', 'American Football', 'Chiefs vs Bills', 'Bills +3', 25, 1.95, BetStatus.won, null),
    ('2026-08-22', 'Soccer', 'Inter vs Napoli', 'Draw', 15, 3.30, BetStatus.lost, null),
    ('2026-08-28', 'Basketball', 'Nuggets vs Suns', 'Over 228.5', 20, 1.87, BetStatus.lost, null),
    ('2026-09-04', 'Tennis', 'Swiatek vs Gauff', 'Swiatek 2-0', 20, 1.75, BetStatus.won, null),
    ('2026-09-11', 'Baseball', 'Dodgers vs Padres', 'Dodgers ML', 25, 1.70, BetStatus.push, null),
    ('2026-09-18', 'Soccer', 'Bayern vs Dortmund', 'Both teams to score', 20, 1.62, BetStatus.won, null),
    ('2026-09-25', 'Esports', 'LoL Worlds', 'T1 to win', 15, 1.55, BetStatus.lost, null),
    ('2026-10-02', 'American Football', 'Eagles vs Cowboys', 'Eagles ML', 30, 1.80, BetStatus.cashout, 41),
    ('2026-10-09', 'Soccer', 'Barcelona vs Atlético', 'Barcelona to win', 25, 2.10, BetStatus.won, null),
    ('2026-10-15', 'Ice Hockey', 'Oilers vs Flames', 'Oilers ML', 20, 1.75, BetStatus.pending, null),
    ('2026-10-16', 'Soccer', 'Man City vs Arsenal', 'Arsenal +0.5', 25, 1.95, BetStatus.pending, null),
  ];
  for (final r in rows) {
    await db.saveBet(
      Bet(
        date: r.$1,
        sport: r.$2,
        event: r.$3,
        selection: r.$4,
        stake: r.$5,
        odds: r.$6,
        status: r.$7,
        cashout: r.$8,
        created: '${r.$1}T12:00:00',
      ),
    );
  }
  await db.saveBet(
    Bet(
      type: BetType.parlay,
      selection: '3-leg parlay',
      sport: 'Mixed',
      date: '2026-10-12',
      stake: 10,
      odds: 1.8 * 1.65 * 2.05,
      created: '2026-10-12T12:00:00',
      status: BetStatus.won,
      legs: const [
        BetLeg(
          selection: 'Liverpool ML',
          event: 'Liverpool vs Everton',
          sport: 'Soccer',
          odds: 1.8,
          status: BetStatus.won,
        ),
        BetLeg(
          selection: 'Celtics -3.5',
          event: 'Celtics vs Heat',
          sport: 'Basketball',
          odds: 1.65,
          status: BetStatus.won,
        ),
        BetLeg(selection: 'Over 2.5 goals', event: 'PSG vs Lyon', sport: 'Soccer', odds: 2.05, status: BetStatus.won),
      ],
    ),
  );
  await db.saveTx(const BankTx(kind: TxKind.deposit, amount: 200, date: '2026-08-01', note: 'Top up'));
  await db.setPref('matches.country', 'eng');
  final store = BankStore(db);
  await store.load();
  return store;
}

void main() {
  sqfliteFfiInit();
  final shots = Platform.environment['SCREENSHOTS'] == '1';

  testWidgets('summary, register, form with parlay legs, and charts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/$name.png'));
    }

    final store = (await tester.runAsync(seededStore))!;
    await tester.pumpWidget(
      BankTrackApp(
        store: store,
        fixtures: FixturesApi(client: _fixturesClient()),
        today: DateTime(2026, 10, 18),
      ),
    );
    await tester.pumpAndSettle();

    // Summary is the main page and holds no bet list.
    expect(find.text('BANKROLL'), findsOneWidget);
    expect(find.text('ROI'), findsOneWidget);
    expect(find.text('Barcelona to win'), findsNothing);
    await shot('summary');

    // Bet register tab.
    await tester.tap(find.text('Bets'));
    await tester.pumpAndSettle();
    expect(find.text('Bet register'), findsOneWidget);
    expect(find.text('3-leg parlay'), findsOneWidget);
    await shot('bets');

    // Settle the newest open bet as won.
    final before = store.stats.wins;
    final won = find.widgetWithText(OutlinedButton, 'Won').first;
    await tester.ensureVisible(won);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(won);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.stats.wins, before + 1);

    // Log-a-bet form, single then parlay.
    await tester.tap(find.text('Log bet'));
    await tester.pumpAndSettle();
    expect(find.text('Log a bet'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Selection, e.g. Arsenal to win'), 'Arsenal to win');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Event (optional), e.g. Arsenal vs Chelsea'),
      'Arsenal vs Chelsea',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '2.50'), '2.10');
    await tester.pumpAndSettle();
    expect(find.text('\$42.00'), findsOneWidget);
    expect(find.text('Returns \$42.00'), findsOneWidget);
    await shot('log_bet');

    await tester.tap(find.text('Parlay'));
    await tester.pumpAndSettle();
    final legSelection = find.widgetWithText(TextFormField, 'Selection');
    expect(legSelection, findsNWidgets(2));
    // Leg 1 carried over what was typed for the single.
    expect(tester.widget<TextFormField>(legSelection.first).controller!.text, 'Arsenal to win');
    await tester.enterText(legSelection.at(1), 'Lakers ML');
    await tester.enterText(find.widgetWithText(TextFormField, '2.50').at(1), '1.50');
    await tester.pumpAndSettle();
    expect(find.text('Combined 3.15'), findsOneWidget);
    await shot('log_parlay');

    await tester.runAsync(() async {
      await tester.tap(find.text('Log bet').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final saved = store.bets.firstWhere((b) => b.isParlay && b.status == BetStatus.pending);
    expect(saved.legs.map((l) => l.selection), ['Arsenal to win', 'Lakers ML']);
    expect(saved.odds, closeTo(3.15, 1e-9));

    // Matches.
    await tester.tap(find.text('Matches'));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    }
    await tester.pumpAndSettle();
    expect(find.text('England'), findsOneWidget);
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('PREMIER LEAGUE'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    await shot('matches');

    await tester.tap(find.text('Arsenal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log a bet on this match'));
    await tester.pumpAndSettle();
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Tapping a price pre-fills the pick and the odds.
    await tester.tap(find.text('2.10'));
    await tester.pumpAndSettle();
    expect(find.text('AFC Bournemouth vs Sunderland'), findsOneWidget);
    expect(find.text('AFC Bournemouth to win'), findsOneWidget);
    expect(find.text('2.10'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Charts.
    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('Bankroll over time'), findsOneWidget);
    await shot('charts');
  });
}

http.Client _fixturesClient() => MockClient((req) async {
  if (req.url.queryParameters['dates'] != '20261018') return http.Response(board([]), 200);
  return switch (req.url.pathSegments[req.url.pathSegments.length - 2]) {
    'eng.1' => http.Response(
      board([
        espnEvent(
          '1',
          '2026-10-18T11:30:00Z',
          'Leeds United',
          'Everton',
          state: 'post',
          completed: true,
          detail: 'FT',
          hs: '0',
          as: '3',
        ),
        espnEvent('2', '2026-10-18T14:00:00Z', 'Arsenal', 'Chelsea', state: 'in', detail: "67'", hs: '2', as: '1'),
        espnEvent('3', '2026-10-18T16:30:00Z', 'AFC Bournemouth', 'Sunderland', odds: [2.1, 3.4, 3.6]),
        espnEvent('4', '2026-10-18T19:00:00Z', 'Manchester City', 'Liverpool'),
      ]),
      200,
    ),
    'eng.2' => http.Response(
      board([
        espnEvent('5', '2026-10-18T14:00:00Z', 'Coventry City', 'Middlesbrough'),
        espnEvent('6', '2026-10-18T14:00:00Z', 'Norwich City', 'Watford'),
      ]),
      200,
    ),
    _ => http.Response(board([]), 200),
  };
});
