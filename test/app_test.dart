import 'dart:io';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/main.dart';
import 'package:bank_track/ui/match_page.dart';
import 'package:bank_track/ui/matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bank_track/data/fixtures.dart';

import 'fixtures_test.dart' show espnEvent, board;
import 'slip_reader_test.dart' show screen;
import 'package:bank_track/logic/slip_reader.dart';
import 'package:bank_track/ui/slip_import.dart';

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
    MatchesScreen.debugToday = DateTime(2026, 10, 18);
    addTearDown(() => MatchesScreen.debugToday = null);
    await tester.pumpWidget(
      BankTrackApp(
        store: store,
        fixtures: FixturesApi(client: _fixturesClient()),
        today: DateTime(2026, 10, 18),
      ),
    );
    await tester.pumpAndSettle();
    // Load the brand icon so the header shows it in screenshots.
    await tester.runAsync(() => precacheImage(const AssetImage('assets/brand/icon.png'), tester.element(find.byType(BrandTitle))));
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

    await tester.ensureVisible(find.text('Parlay'));
    await tester.pumpAndSettle();
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

    // A third leg picked from the real matches: a tapped price fills it in.
    await tester.ensureVisible(find.byKey(const Key('add-leg-from-matches')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-leg-from-matches')));
    await settle(tester);
    expect(find.text('Pick a selection'), findsOneWidget);
    await tester.tap(find.text('2.10'));
    await settle(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Log bet').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final saved = store.bets.firstWhere((b) => b.isParlay && b.status == BetStatus.pending);
    expect(saved.legs.map((l) => l.selection), ['Arsenal to win', 'Lakers ML', 'AFC Bournemouth to win']);
    expect(saved.legs.last.event, 'AFC Bournemouth vs Sunderland');
    expect(saved.legs.last.sport, 'Soccer');
    expect(saved.odds, closeTo(3.15 * 2.1, 1e-9));

    // Matches. Let the "Bet logged" message time out first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Bet Tools lives in the side menu; Matches is a bottom tab.
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Bet Tools'), findsOneWidget);
    await shot('drawer');
    Navigator.of(tester.element(find.byType(NavigationDrawer))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Matches'));
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

    // A match opens its own page with tabs.
    await tester.tap(find.text('Everton'));
    await settle(tester);
    expect(find.text('DraftKings'.toUpperCase()), findsOneWidget);
    expect(find.text('BET 365'), findsOneWidget);
    await shot('match_odds');
    await openTab(tester, 'Teams');
    expect(find.text('FORM GUIDE'), findsOneWidget);
    expect(find.text('Last 5: 9 of 15 points · scored 6, conceded 4 in 5'), findsOneWidget);
    await shot('match_teams');
    await openTab(tester, 'News');
    await shot('match_news');
    await openTab(tester, 'Table');
    expect(find.text('Manchester City'), findsWidgets);
    expect(find.text('Level on 10 points, 1 place apart.'), findsOneWidget);
    await shot('match_table');

    // Money movement: DraftKings opened Chelsea at +130, now +120.
    await openTab(tester, 'Money');
    await settle(tester);
    expect(find.text('Money is moving towards Chelsea'), findsOneWidget);
    expect(find.textContaining('DraftKings prices since they opened'), findsOneWidget);
    await shot('match_money');

    // Any market with your own odds: a handicap on Chelsea, logged as a bet.
    await openTab(tester, 'Odds');
    await tester.tap(find.text('More markets: handicap, corners, cards…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Chelsea'));
    await tester.enterText(find.widgetWithText(TextField, 'Odds'), '1.95');
    await tester.pumpAndSettle();
    expect(find.text('Chelsea -0.5'), findsOneWidget);
    await shot('markets');
    await tester.ensureVisible(find.text('Use this pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log as a single bet'));
    await tester.pumpAndSettle();
    expect(find.text('Market: Handicap'), findsOneWidget);
    await tester.tap(find.text('Log bet').last);
    await settle(tester);
    final handicap = store.bets.firstWhere((b) => b.selection == 'Chelsea -0.5');
    expect(handicap.market, 'handicap');
    expect(handicap.matchId, '401878771');
    expect(handicap.odds, closeTo(1.95, 1e-9));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Matchboard: open the match's workspace, ask, and the answer lands on the board.
    await tester.tap(find.byTooltip('Open in Matchboard'));
    await settle(tester);
    expect(find.text('Ask about Everton vs Chelsea'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'How are both teams in form?');
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5)); // let the "Saved to the board" message go
    await tester.pumpAndSettle();
    await tester.tap(find.text('Who is the favourite?'));
    await settle(tester);
    expect(find.textContaining('Market favourite: Chelsea'), findsWidgets);
    await shot('matchboard_chat');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Board (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Match summary'), findsOneWidget);
    expect(find.text('Recent form'), findsOneWidget);
    await shot('matchboard_board');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log a bet'));
    await tester.pumpAndSettle();
    expect(find.text('Everton vs Chelsea'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Tapping a price offers a single bet or a parlay; the single pre-fills the form.
    await tester.tap(find.text('2.10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log as a single bet'));
    await tester.pumpAndSettle();
    expect(find.text('AFC Bournemouth vs Sunderland'), findsOneWidget);
    expect(find.text('AFC Bournemouth to win'), findsOneWidget);
    expect(find.text('2.10'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Two picks go into a new parlay.
    await tester.tap(find.text('2.10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new parlay'));
    await settle(tester);
    expect(find.text('Added to Parlay 1 · 1 pick'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.20'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Parlay 1'));
    await settle(tester);
    expect(store.parlays.single.legs.map((l) => l.selection), ['AFC Bournemouth to win', 'Chelsea to win']);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // The Live tab groups live matches by country and league.
    await tester.tap(find.widgetWithText(Tab, 'Live'));
    await settle(tester);
    expect(find.textContaining('2 live now'), findsOneWidget);
    expect(find.text('ENGLAND · PREMIER LEAGUE'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Arsenal')).dy, lessThan(tester.getTopLeft(find.text('Real Madrid')).dy));
    await shot('live');

    // Star a match; it shows under Favorites with its live score.
    await tester.tap(find.byTooltip('Add to favorites').first);
    await settle(tester);
    expect(store.favorites.single.home, 'Arsenal');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Favorites'));
    await settle(tester);
    expect(find.text('LIVE NOW · 1'), findsOneWidget);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    await shot('favorites');

    // "Remove all" empties Favorites after asking.
    await tester.tap(find.byKey(const Key('remove-all-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('Remove all favorites?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove all'));
    await settle(tester);
    expect(store.favorites, isEmpty);
    expect(find.text('Tap the star on any match to follow it here.'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Matches'));
    await tester.pumpAndSettle();

    // Bet Tools, from the side menu: Matchboard and the parlay builder.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bet Tools'));
    await tester.pumpAndSettle();
    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('Money movement'), findsNothing);
    await shot('bet_tools');
    await tester.tap(find.text('Matchboard'));
    await settle(tester);
    expect(find.text('Everton vs Chelsea'), findsOneWidget);
    await shot('matchboard');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parlay builder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parlay 1'));
    await tester.pumpAndSettle();
    // A match that isn't listed, typed in.
    await tester.tap(find.text('Other match'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Match'), 'Millonarios vs Nacional');
    await tester.enterText(find.widgetWithText(TextFormField, 'Selection'), 'Millonarios to win');
    await tester.enterText(find.widgetWithText(TextFormField, 'Odds'), '2.00');
    await tester.tap(find.text('Add pick'));
    await settle(tester);
    await tester.runAsync(() async {
      await tester.enterText(find.widgetWithText(TextField, 'Stake'), '10');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final parlay = store.parlays.single;
    expect(parlay.legs.length, 3);
    expect(parlay.odds, closeTo(2.1 * 2.2 * 2.0, 1e-9));
    expect(find.text('\$92.40'), findsOneWidget);
    await shot('parlay');

    final check = find.text('Check parlay');
    await tester.ensureVisible(check);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await settle(tester);
    expect(store.parlays.single.check, isNotNull);
    expect(find.text('Price only'), findsWidgets);
    expect(find.textContaining('Weakest leg'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Check again'), 200, scrollable: find.descendant(of: find.byKey(const Key('parlay-page')), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await shot('parlay_check');

    final result = find.text('Won');
    await tester.scrollUntilVisible(result, 200, scrollable: find.descendant(of: find.byKey(const Key('parlay-page')), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(result);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.parlays.single.status, BetStatus.won);
    expect(store.parlays.single.legs.every((l) => l.status == BetStatus.won), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A slip screenshot from another betting site becomes a parlay.
    SlipImport.pickImage = () async => '/slip.png';
    SlipImport.scanner = _FakeScanner(screen([
      ['Apuesta combinada (3)'],
      ['Millonarios - Santa Fe'],
      ['1X2 Tiempo reglamentario'],
      ['Millonarios', '2,05'],
      ['Junior - Nacional'],
      ['Total de goles'],
      ['Más de 2.5', '1,80'],
      ['América - Cali'],
      ['Ambos equipos marcan'],
      ['Sí', '1,95'],
      ['Cuota total', '7,19'],
      ['Apuesta', '\$ 10.000'],
    ]));
    await tester.tap(find.text('From screenshot'));
    await settle(tester);
    expect(find.textContaining('Read 3 selections'), findsOneWidget);
    expect(find.text('Millonarios - Santa Fe'), findsOneWidget);
    await shot('slip_review');
    await tester.scrollUntilVisible(find.text('Save as a parlay'), 300,
        scrollable: find.descendant(of: find.byKey(const Key('slip-review')), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as a parlay'));
    await settle(tester);
    final imported = store.parlays.firstWhere((p) => p.name == 'Parlay 2');
    expect(imported.legs.map((l) => (l.selection, l.event, l.odds)), [
      ('Millonarios', 'Millonarios - Santa Fe', 2.05),
      ('Más de 2.5', 'Junior - Nacional', 1.80),
      ('Sí · Ambos equipos marcan', 'América - Cali', 1.95),
    ]);
    expect(imported.stake, 10000);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await shot('parlays');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack(); // Bet Tools
    await tester.pumpAndSettle();

    // Settings: pick a theme; it applies straight away and is saved.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Olive & Gold'), findsOneWidget);
    await shot('settings_themes');
    await tester.scrollUntilVisible(find.byKey(const Key('ai-key')), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('AI chat'), findsOneWidget);
    await shot('settings_ai');
    await tester.scrollUntilVisible(find.text('Olive & Gold'), -300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Ocean'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.themeId, 'ocean');
    expect(await tester.runAsync(() => store.pref('app.theme')), 'ocean');
    await shot('settings_ocean');
    await tester.runAsync(() async {
      await tester.tap(find.text('Olive & Gold'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Charts.
    // Review bet from the history: the handicap logged from the match page.
    await tester.tap(find.text('Bets'));
    await tester.pumpAndSettle();
    // By its selection: which bet sorts first depends on today's date.
    await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('Chelsea -0.5'), matching: find.byType(Card)).first, matching: find.text('Review bet')));
    await settle(tester);
    expect(find.text('Since you placed it'), findsOneWidget);
    expect(find.textContaining('Not started yet'), findsOneWidget);
    await shot('bet_review');
    await tester.scrollUntilVisible(find.text('Suggestions'), 300);
    await tester.pumpAndSettle();
    await shot('bet_review_more');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('Bankroll over time'), findsOneWidget);
    await shot('charts');
  });

  testWidgets('finished match page: line-ups, key events and stats', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(MatchPage), matchesGoldenFile('screenshots/$name.png'));
    }

    final store = (await tester.runAsync(seededStore))!;
    final match = Match(
      id: '401877960',
      league: const League('col.1', 'Primera A'),
      kickoff: DateTime.utc(2026, 10, 6),
      home: const Team('Independiente Medellín', 'Medellín', null, '0'),
      away: const Team('Independiente Santa Fe', 'Santa Fe', null, '1'),
      state: MatchState.finished,
      detail: 'FT',
      venue: 'Metropolitano Ciudad de Itagüí',
    );
    await tester.pumpWidget(MaterialApp(
      theme: BankTrackApp.theme('olive'),
      home: MatchPage(match: match, store: store, api: FixturesApi(client: _fixturesClient())),
    ));
    await settle(tester);
    await openTab(tester, 'Line-ups');
    expect(find.text('4-2-3-1'), findsOneWidget);
    await shot('match_lineups');
    await openTab(tester, 'Events');
    expect(find.text('First Half begins.'), findsOneWidget);
    await shot('match_events');
    await openTab(tester, 'Stats');
    expect(find.text('Possession'), findsOneWidget);
    expect(find.text('59.9%'), findsOneWidget);
    await shot('match_stats');
    await openTab(tester, 'H2H');
    await openTab(tester, 'Odds');
    expect(find.text('DRAFTKINGS'), findsOneWidget);
  });
}

/// Lets network futures complete, then settles the frame.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  }
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String name) async {
  final tab = find.widgetWithText(Tab, name);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Match summaries: Everton vs Chelsea before kick-off, anything else a
/// finished Colombian match with line-ups and key events.
http.Response _summary(Uri url) => http.Response.bytes(
      File(url.queryParameters['event'] == '401878771'
              ? 'test/data/espn_summary_pre.json'
              : 'test/data/espn_summary_col.json')
          .readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Client _fixturesClient() => MockClient((req) async {
  if (req.url.pathSegments.last == 'summary') return _summary(req.url);
  final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
  if (!req.url.queryParameters.containsKey('dates')) {
    // Today's scoreboard, used by the Live tab.
    return http.Response(
      board(switch (slug) {
        'eng.1' => [espnEvent('2', '2026-10-18T14:00:00Z', 'Arsenal', 'Tottenham Hotspur', state: 'in', detail: "67'", hs: '2', as: '1')],
        'esp.1' => [espnEvent('9', '2026-10-18T14:00:00Z', 'Real Madrid', 'Getafe', state: 'in', detail: "12'", hs: '0', as: '0')],
        _ => [],
      }),
      200,
    );
  }
  if (req.url.queryParameters['dates'] != '20261018') return http.Response(board([]), 200);
  return switch (req.url.pathSegments[req.url.pathSegments.length - 2]) {
    'eng.1' => http.Response(
      board([
        espnEvent(
          '1',
          '2026-10-18T11:30:00Z',
          'Leeds United',
          'Fulham',
          state: 'post',
          completed: true,
          detail: 'FT',
          hs: '0',
          as: '3',
        ),
        espnEvent('2', '2026-10-18T14:00:00Z', 'Arsenal', 'Tottenham Hotspur', state: 'in', detail: "67'", hs: '2', as: '1'),
        espnEvent('3', '2026-10-18T16:30:00Z', 'AFC Bournemouth', 'Sunderland', odds: [2.1, 3.4, 3.6]),
        espnEvent('401878771', '2026-10-18T19:00:00Z', 'Everton', 'Chelsea', odds: [3.0, 3.8, 2.2]),
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

class _FakeScanner implements SlipScanner {
  _FakeScanner(this.lines);
  final List<SlipLine> lines;
  @override
  Future<List<SlipLine>> scan(String imagePath) async => lines;
}
