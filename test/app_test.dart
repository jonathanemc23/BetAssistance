import 'dart:convert';
import 'dart:io';

import 'package:bank_track/data/account.dart';
import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/main.dart';
import 'package:bank_track/ui/account_screens.dart' show LoginPage;
import 'package:bank_track/ui/community.dart' show BettorProfilePage;
import 'package:bank_track/ui/match_page.dart';
import 'package:bank_track/ui/match_visuals.dart';
import 'package:bank_track/ui/matches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bank_track/data/fixtures.dart';

import 'fixtures_test.dart' show espnEvent, board;
import 'slip_reader_test.dart' show screen;
import 'stake_community_test.dart' show boxSummary;
import 'package:bank_track/l10n/l10n.dart';
import 'package:bank_track/logic/community.dart';
import 'package:bank_track/logic/slip_reader.dart';
import 'package:bank_track/logic/stake_stats.dart';
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
  // The legend avatars' emblems.
  for (final (family, file) in [
    ('FontAwesomeSolid', 'Font-Awesome-7-Free-Solid-900.otf'),
    ('FontAwesomeRegular', 'Font-Awesome-7-Free-Regular-400.otf'),
    ('FontAwesomeBrands', 'Font-Awesome-7-Brands-Regular-400.otf'),
  ]) {
    await (FontLoader('packages/font_awesome_flutter/$family')
          ..addFont(rootBundle.load('packages/font_awesome_flutter/lib/fonts/$file')))
        .load();
  }
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
  await db.setPref('app.language', 'en');
  await db.setPref('stake.picks', '[]');
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

    // Home: the bank with highlights, the day's important matches, Pro tips
    // and free tips.
    await settle(tester);
    expect(find.text('BANK'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('2 open bets'), findsOneWidget);
    expect(find.text('Important matches today'), findsOneWidget);
    expect(find.text('Arsenal'), findsOneWidget); // live
    expect(find.text('AFC Bournemouth'), findsOneWidget);
    expect(find.text('Leeds United'), findsNothing); // finished: not in the strip
    expect(find.text('Barcelona to win'), findsNothing);
    await shot('home');
    await tester.scrollUntilVisible(find.text('Free tips'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-pro-tips')), findsOneWidget);
    await shot('home_tips');
    await tester.drag(find.text('Free tips'), const Offset(0, 2000));
    await tester.pumpAndSettle();

    // The avatar is picked from Home, and shows there.
    await tester.tap(find.byKey(const Key('home-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Choose your avatar'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('avatar-legend:oracle')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.avatar, 'legend:oracle');
    await shot('avatar_picker');
    Navigator.of(tester.element(find.text('Choose your avatar'))).pop();
    await tester.pumpAndSettle();

    // The full summary is one tap away and holds no bet list.
    await tester.tap(find.text('See summary'));
    await tester.pumpAndSettle();
    expect(find.text('BANKROLL'), findsOneWidget);
    expect(find.text('ROI'), findsOneWidget);
    expect(find.text('Barcelona to win'), findsNothing);
    await shot('summary');
    await tester.pageBack();
    await tester.pumpAndSettle();

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
    // It opens on the overview: chances from the odds, form and the table.
    expect(find.text('WIN CHANCES'), findsOneWidget);
    expect(find.text('FORM GUIDE'), findsOneWidget);
    await shot('match_overview');
    await openTab(tester, 'Odds');
    expect(find.text('DraftKings'.toUpperCase()), findsOneWidget);
    expect(find.text('BET 365'), findsOneWidget);
    await shot('match_odds');
    await openTab(tester, 'Teams');
    expect(find.text('FORM GUIDE'), findsOneWidget);
    expect(find.text('Last 5: 7 of 15 points · scored 7, conceded 7 in 5'), findsNWidgets(2));
    await shot('match_teams');
    // Ten latest results for each side, read from the teams' schedules.
    final teamsList = find.descendant(of: find.byType(TabBarView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('at Opponent 2'), 200, scrollable: teamsList);
    await tester.scrollUntilVisible(find.text('at Opponent 10'), 200, scrollable: teamsList);
    expect(find.text('at Opponent 12'), findsNothing);
    await openTab(tester, 'H2H');
    expect(find.text('LAST 10 MEETINGS'), findsOneWidget);
    await shot('match_h2h_ten');
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

    // Pro tips: free daily tips under the promo, then a Pro tip bought with tokens.
    await tester.tap(find.text('Pro tips'));
    await settle(tester);
    expect(find.text('Get our full bet analysis'), findsOneWidget);
    expect(find.text('FREE TODAY'), findsOneWidget);
    expect(find.textContaining('Value +'), findsWidgets);
    await shot('pro_tips_daily');
    await tester.tap(find.text('See Pro tips'));
    await tester.pumpAndSettle();
    expect(store.tokens, BankStore.starterTokens);
    expect(find.textContaining('Buy prediction'), findsWidgets);
    await shot('pro_tips_locked');
    await tester.tap(find.textContaining('Buy prediction').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Buy prediction'));
    await settle(tester);
    expect(store.unlockedTips, hasLength(1));
    expect(store.tokens, BankStore.starterTokens - store.unlockedTips.values.single.cost);
    await shot('pro_tips_unlocked');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
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

    // Bet Tools, from the side menu: Pro tips and the parlay builder.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bet Tools'));
    await tester.pumpAndSettle();
    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('Money movement'), findsNothing);
    expect(find.text('Pro tips'), findsOneWidget);
    await shot('bet_tools');

    // Pro tips from Bet Tools: the day's page, not a match page.
    await tester.tap(find.text('Pro tips'));
    await settle(tester);
    expect(find.text('Search a match'), findsOneWidget);
    expect(find.text("Today's best value bets"), findsOneWidget);
    expect(find.text("RECOMMENDED FOR TODAY'S BIG MATCHES"), findsOneWidget);
    expect(find.text('Everton vs Chelsea'), findsWidgets);
    await shot('pro_tips_hub');
    await tester.tap(find.widgetWithText(Tab, 'Pro tips'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The more a Pro tip costs, the better its odds'), findsOneWidget);
    expect(find.textContaining('Buy prediction'), findsWidgets);
    await shot('pro_tips_hub_pro');
    await tester.tap(find.byKey(const Key('search-match')));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'chel');
    await tester.pumpAndSettle();
    expect(find.text('Everton vs Chelsea'), findsOneWidget);
    expect(find.text('Arsenal vs Tottenham Hotspur'), findsNothing);
    await shot('pro_tips_search');
    await tester.tap(find.text('Everton vs Chelsea'));
    await settle(tester);
    expect(find.text('FREE TODAY'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
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

  testWidgets('stake builder: match stats, picks from two matches, validate', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/$name.png'));
    }

    final store = (await tester.runAsync(seededStore))!;
    await tester.pumpWidget(
      BankTrackApp(store: store, fixtures: FixturesApi(client: _fixturesClient()), today: DateTime(2026, 10, 18)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    // The menu: Bet Tools, then Community as one entry; the stake builder lives in Bet Tools.
    expect(find.byKey(const Key('drawer-community')), findsOneWidget);
    expect(find.byKey(const Key('drawer-stake')), findsNothing);
    expect(find.text('Become a pro bettor'), findsNothing);
    await tester.tap(find.byKey(const Key('drawer-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Community'), findsNothing);
    await tester.tap(find.text('Stake builder'));
    await tester.pumpAndSettle();
    expect(find.text('Build a stake from match stats'), findsOneWidget);

    // Pick a match: the day's soccer matches.
    await tester.tap(find.byKey(const Key('stake-pick-match')));
    await settle(tester);
    expect(find.text('Everton vs Chelsea'), findsOneWidget);
    await tester.tap(find.text('Everton vs Chelsea'));
    await settle(tester);

    // Both teams' last six games with their scores, and a card per stat.
    expect(find.text('Everton'), findsWidgets);
    expect(find.byKey(const Key('stake-stat-goals')), findsOneWidget);
    expect(find.byKey(const Key('stake-stat-corners')), findsOneWidget);
    await shot('stake_stats');
    final corners = find.byWidgetPredicate((w) => '${w.key}'.contains('stake-line-corners-match-over-'), skipOffstage: false);
    await tester.ensureVisible(corners.first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(corners.first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.stake, hasLength(1));
    expect(store.stake.single.stat.name, 'corners');
    await shot('stake_stats_corners');
    final goals = find.byWidgetPredicate((w) => '${w.key}'.contains('stake-line-goals-match-over-'), skipOffstage: false);
    await tester.ensureVisible(goals.first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(goals.first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.stake, hasLength(2));
    await tester.tap(find.byKey(const Key('stake-view')));
    await tester.pumpAndSettle();

    // A second match in the same stake.
    expect(find.text('Validate stake (2 picks)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('stake-add-match')));
    await settle(tester);
    await tester.tap(find.text('AFC Bournemouth vs Sunderland'));
    await settle(tester);
    expect(find.text('No recent games with stats for these teams yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(() => store.addStakePick(StakePick(
          matchId: '3',
          leagueSlug: 'eng.1',
          leagueName: 'Premier League',
          home: 'AFC Bournemouth',
          away: 'Sunderland',
          kickoff: DateTime.utc(2026, 10, 18, 16, 30),
          stat: StakeStat.cards,
          scope: StakeScope.match,
          over: true,
          line: 3.5,
          hitRate: 0.5,
          average: 3.4,
        )));
    await tester.pumpAndSettle();
    await shot('stake_builder');

    // Validate: each pick against its match.
    await tester.tap(find.byKey(const Key('stake-validate')));
    await settle(tester);
    expect(find.byKey(const Key('stake-review')), findsOneWidget);
    expect(find.textContaining('chance that every pick comes in'), findsOneWidget);
    expect(find.textContaining('of the last 12 games'), findsWidgets);
    await shot('stake_validated');

    // The stake is kept when the app opens again.
    expect((await tester.runAsync(() => store.pref('stake.picks')))!, contains('"stat":"corners"'));
  });

  testWidgets('community: sign in, unique nametag, carousel and tabs, bettor profile, chat, challenge', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/$name.png'));
    }

    communityClock = () => DateTime.utc(2026, 10, 18, 10);
    addTearDown(() => communityClock = DateTime.now);
    final store = (await tester.runAsync(seededStore))!;
    final server = _CommunityServer();
    final account = AccountService(store: store, apiKey: 'k', server: 'https://server.example.com', client: server.client());
    await tester.pumpWidget(
      BankTrackApp(store: store, fixtures: FixturesApi(client: _fixturesClient()), today: DateTime(2026, 10, 18), account: account),
    );
    await tester.pumpAndSettle();
    if (find.byType(LoginPage).evaluate().isNotEmpty) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-community')));
    await tester.pumpAndSettle();

    // Signed out: sign in first.
    expect(find.text('Sign in to join the community'), findsOneWidget);
    await shot('community_sign_in');
    await tester.runAsync(() async {
      expect(await account.signIn('laura@example.com', 'secret1'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);

    // Then a community profile, with a nametag no one else has.
    expect(find.text('Join the community'), findsOneWidget);
    expect(find.textContaining('become a pro bettor yourself'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-name')), 'Laura');
    await tester.enterText(find.byKey(const Key('community-handle')), 'goalmachine');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('That nametag is taken. Try another one.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-handle')), 'a');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('community-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-create')));
    await tester.pumpAndSettle();
    expect(find.text('3 to 20 letters, digits or _'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-handle')), '@Laura_Bets');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('@laura_bets is yours to take'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('community-bio')), 'Corners and goals, Premier League.');
    await tester.pumpAndSettle();
    await shot('community_profile_create');
    await tester.ensureVisible(find.byKey(const Key('community-create')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('community-create')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    expect(server.created, ['laura_bets']);
    expect(store.socialProfile!.handle, 'laura_bets');

    // The community: tokens by the avatar, a closable pro bettor alert, the
    // hottest bets in a carousel, then the tabs.
    expect(find.byKey(const Key('community-tokens')), findsOneWidget);
    expect(find.byKey(const Key('community-pro-alert')), findsOneWidget);
    expect(find.byKey(const Key('community-hot-carousel')), findsOneWidget);
    expect(find.byKey(const Key('community-tabs')), findsOneWidget);
    await shot('community_home');
    await tester.tap(find.byKey(const Key('community-pro-alert-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('community-pro-alert')), findsNothing);
    expect(await tester.runAsync(() => store.pref('community.proAlertClosed')), '1');

    // Buy from the carousel: the pick shows once bought.
    final tokens = store.tokens;
    await tester.tap(find.byWidgetPredicate((w) => '${w.key}'.contains("'hot-buy-")).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Buy'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.boughtListings, hasLength(1));
    expect(store.tokens, lessThan(tokens));
    expect(find.text('${store.tokens}'), findsWidgets);

    // Free bets: follow a bettor, post one of your own.
    final follow = find.byWidgetPredicate((w) => '${w.key}'.contains("'follow-"), skipOffstage: false);
    await tester.scrollUntilVisible(follow.first, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(follow.first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.following, hasLength(1));
    await shot('community_free_bets');
    await tester.ensureVisible(find.byKey(const Key('community-post-free')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-post-free')));
    await settle(tester);
    await tester.tap(find.text('Everton vs Chelsea').last);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('market-awayWin'), skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('market-awayWin')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.myFreeBets, hasLength(1));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last)).clearSnackBars();
    await tester.pumpAndSettle();

    // Buy bets, and a seller's public profile from their avatar.
    await tester.scrollUntilVisible(find.byKey(const Key('community-tabs'), skipOffstage: false), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('community-tabs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-tab-buy')));
    await tester.pumpAndSettle();
    expect(find.textContaining('pick hidden'), findsWidgets);
    final avatar = find.byWidgetPredicate((w) => '${w.key}'.contains("'avatar-"), skipOffstage: false);
    await tester.ensureVisible(avatar.first);
    await tester.pumpAndSettle();
    await tester.tap(avatar.first);
    await tester.pumpAndSettle();
    expect(find.byType(BettorProfilePage), findsOneWidget);
    expect(find.text('Bets sold'), findsOneWidget);
    expect(find.text('Average odds'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    await shot('community_bettor');
    await tester.tap(find.byKey(const Key('bettor-rate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rate-star-4')));
    await tester.enterText(find.byKey(const Key('rate-comment')), 'Clear picks.');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.myReviews.values.single.stars, 4);
    expect(find.text('Clear picks.'), findsOneWidget);

    // A message to the bettor, then the Chat tab lists it.
    await tester.tap(find.byKey(const Key('bettor-message')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-input')), 'Hi! Any picks for Sunday?');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('chat-send')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.chats.values.single.single.text, 'Hi! Any picks for Sunday?');
    expect(find.text('Hi! Any picks for Sunday?'), findsOneWidget);
    await shot('community_chat');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('community-tabs'), skipOffstage: false), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('community-tabs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('community-tab-chat')));
    await tester.pumpAndSettle();
    expect(find.text('Hi! Any picks for Sunday?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-tab-history')));
    await tester.pumpAndSettle();
    expect(find.text('Bets you bought'), findsOneWidget);
    expect(find.text('Your free bets'), findsOneWidget);

    // The profile: Following only until pro; the challenge starts here.
    await tester.tap(find.byKey(const Key('community-profile')));
    await tester.pumpAndSettle();
    expect(find.text('@laura_bets'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Followers'), findsNothing);
    expect(find.text('Bets bought'), findsNothing);
    await shot('community_profile');
    await tester.tap(find.byKey(const Key('profile-pass-challenge')));
    await tester.pumpAndSettle();
    expect(find.text('How it works'), findsOneWidget);
    expect(find.textContaining('odds over 1.60'), findsWidgets);
    await shot('community_pro_bettor');
    await tester.scrollUntilVisible(find.byKey(const Key('challenge-accept')), 300, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-accept')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('0 of 30 bets'), findsOneWidget);
    await tester.tap(find.byKey(const Key('challenge-place')));
    await settle(tester);
    await tester.tap(find.text('Everton vs Chelsea').last);
    await settle(tester);
    expect(find.text('Pick your bet: odds over 1.60'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('market-awayWin'), skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('market-awayWin')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Place bet'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.challenge.placed, 1);

    // As a pro: followers and the record of the bets sold.
    await tester.runAsync(() async {
      await store.setPref('community.challenge', jsonEncode(ProChallenge(passedAt: DateTime.utc(2026, 10, 1)).toJson()));
      await store.load();
    });
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Followers'), findsOneWidget);
    expect(find.text('Bets sold'), findsOneWidget);
    expect(find.byKey(const Key('profile-pass-challenge')), findsNothing);
  });

  testWidgets('Spanish: the language setting switches every screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/$name.png'));
    }

    final store = (await tester.runAsync(seededStore))!;
    addTearDown(() => L10n.use(AppLanguage.en));
    await tester.pumpWidget(
      BankTrackApp(store: store, fixtures: FixturesApi(client: _fixturesClient()), today: DateTime(2026, 10, 18)),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Español'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(store.language, AppLanguage.es);
    expect(await tester.runAsync(() => store.pref('app.language')), 'es');
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Tema'), findsOneWidget);
    await shot('es_settings');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Home, the register and the side menu.
    expect(find.text('BANCA'), findsOneWidget);
    expect(find.text('Partidos importantes de hoy'), findsOneWidget);
    await shot('es_home');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Apuestas'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar apuesta'), findsOneWidget);
    await shot('es_bets');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Comunidad'), findsOneWidget);
    await shot('es_drawer');

    // The pro bettor page.
    communityClock = () => DateTime.utc(2026, 10, 18, 10);
    addTearDown(() => communityClock = DateTime.now);
    await tester.runAsync(() async {
      await store.saveSocialProfile(
          const SocialProfile(name: 'Laura', handle: 'laura_bets', avatar: 'legend:oracle', joined: '2026-10-18T10:00:00'));
      // Not a pro yet, whatever an earlier test left in the shared database.
      await store.setPref('community.challenge', '{}');
      await store.load();
    });
    await tester.tap(find.byKey(const Key('drawer-community')));
    await settle(tester);
    expect(find.text('Las apuestas más compradas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-profile')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('profile-pass-challenge')));
    await settle(tester);
    expect(find.text('Requisitos'), findsOneWidget);
    expect(find.textContaining('haz al menos 30 apuestas'), findsOneWidget);
    await shot('es_pro_bettor');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }

    // The stake builder with a match's stats.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Constructor de apuestas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stake-pick-match')));
    await settle(tester);
    await tester.tap(find.text('Everton vs Chelsea'));
    await settle(tester);
    expect(find.text('Goles'), findsOneWidget);
    expect(find.text('Más de 2.5 · 67%'), findsOneWidget);
    await shot('es_stake_stats');

    // Back to English.
    await tester.runAsync(() => store.setLanguage(AppLanguage.en));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
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
    expect(find.byType(LineupPitch), findsOneWidget);
    expect(find.textContaining('4-4-1-1'), findsOneWidget); // the away side, above the pitch
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

  testWidgets('match with shot positions: overview, stat tiles, shot map, table with crests', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);
    Future<void> shot(String name) async {
      if (shots) await expectLater(find.byType(MatchPage), matchesGoldenFile('screenshots/$name.png'));
    }

    final store = (await tester.runAsync(seededStore))!;
    final match = Match(
      id: '401879260',
      league: const League('eng.1', 'Premier League'),
      kickoff: DateTime.utc(2026, 10, 18, 13),
      home: const Team('Leeds United', 'Leeds', null, '1'),
      away: const Team('Manchester United', 'Man United', null, '1'),
      state: MatchState.finished,
      detail: 'FT',
      venue: 'Elland Road',
    );
    await tester.pumpWidget(MaterialApp(
      theme: BankTrackApp.theme('olive'),
      home: MatchPage(match: match, store: store, api: FixturesApi(client: _fixturesClient())),
    ));
    await settle(tester);
    expect(find.text('KEY STATS'), findsOneWidget);
    expect(find.text('Corners'), findsOneWidget);
    expect(find.text('Mbeumo 35\''), findsOneWidget); // scorer under the score
    await shot('match_overview_live');
    await openTab(tester, 'Stats');
    expect(find.byType(StatTiles), findsOneWidget);
    await shot('match_stats_tiles');
    expect(find.byType(ShotMap, skipOffstage: false), findsOneWidget);
    if (shots) {
      final list = find.descendant(of: find.byType(TabBarView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('SHOT MAP'), 200, scrollable: list);
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      await shot('match_shot_map');
    }
    await openTab(tester, 'Table');
    expect(find.text('Leeds United'), findsWidgets);
    await shot('match_table_crests');
    await openTab(tester, 'Line-ups');
    expect(find.byType(LineupPitch), findsOneWidget);
    expect(find.text('Mbeumo'), findsOneWidget);
    await shot('match_lineup_pitch');
    await openTab(tester, 'Events');
    await shot('match_timeline');
    await openTab(tester, 'H2H');
    await shot('match_h2h');
  });
  _zonesTest();
  _parlayPickTest();
}

void _zonesTest() {
  testWidgets('teams from different zones: both groups in the table', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final shots = Platform.environment['SCREENSHOTS'] == '1';
    if (shots) await tester.runAsync(loadFonts);
    final store = (await tester.runAsync(seededStore))!;
    final match = Match(
      id: '401841641',
      league: const League('arg.1', 'Liga Profesional'),
      kickoff: DateTime.utc(2026, 10, 24, 17, 45),
      home: const Team('Banfield', 'Banfield', null, null),
      away: const Team('Lanús', 'Lanús', null, null),
      state: MatchState.scheduled,
      detail: '',
    );
    await tester.pumpWidget(MaterialApp(
      theme: BankTrackApp.theme('olive'),
      home: MatchPage(match: match, store: store, api: FixturesApi(client: _fixturesClient())),
    ));
    await settle(tester);
    await openTab(tester, 'Table');
    expect(find.text('Group with Banfield'), findsOneWidget);
    expect(find.text('Group with Lanús', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('In different groups'), findsOneWidget);
    if (shots) await expectLater(find.byType(MatchPage), matchesGoldenFile('screenshots/match_table_zones.png'));
  });

  testWidgets('NBA game: a Players tab with both teams\' box scores, sortable, with each player\'s line', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final shots = Platform.environment['SCREENSHOTS'] == '1';
    if (shots) await tester.runAsync(loadFonts);
    final store = (await tester.runAsync(seededStore))!;
    final match = Match(
      id: '401809997',
      league: const League('nba', 'NBA', sport: Sport.basketball),
      kickoff: DateTime.utc(2025, 11, 1, 23),
      home: const Team('Milwaukee Bucks', 'Bucks', null, '133'),
      away: const Team('Sacramento Kings', 'Kings', null, '135'),
      state: MatchState.finished,
      detail: 'Final',
    );
    await tester.pumpWidget(MaterialApp(
      theme: BankTrackApp.theme('olive'),
      home: MatchPage(match: match, store: store, api: FixturesApi(client: _fixturesClient())),
    ));
    await settle(tester);
    await openTab(tester, 'Players');
    // The home team first, starters then the bench, and the team's totals.
    expect(find.text('G. Antetokounmpo'), findsOneWidget);
    expect(find.text('STARTERS'), findsOneWidget);
    expect(find.text('BENCH'), findsOneWidget);
    expect(find.text('Team totals'), findsOneWidget);
    expect(find.text('PTS'), findsOneWidget);
    expect(find.text('133'), findsWidgets);
    expect(find.text('DID NOT PLAY', skipOffstage: false), findsOneWidget);
    // Points, rebounds and assists lead; the column at the right edge is cut
    // half-way to show the table scrolls.
    final heads = ['PTS', 'REB', 'AST', 'MIN'].map((h) => tester.getTopLeft(find.text(h)).dx).toList();
    expect(heads, orderedEquals([...heads]..sort()));
    final table = tester.getRect(find.byType(SingleChildScrollView).last);
    final cutHeads = [
      for (final e in find.descendant(of: find.byType(SingleChildScrollView).last, matching: find.byType(Tooltip)).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ].where((r) => r.left < table.right && r.right > table.right);
    expect(cutHeads, hasLength(1));
    final cut = cutHeads.single;
    expect((table.right - cut.left) / cut.width, closeTo(0.5, 0.15));
    if (shots) await expectLater(find.byType(MatchPage), matchesGoldenFile('screenshots/match_players.png'));

    // The other team.
    await tester.tap(find.text('Kings'));
    await tester.pumpAndSettle();
    expect(find.text('D. Sabonis'), findsOneWidget);
    expect(find.text('G. Antetokounmpo'), findsNothing);

    // Sorted by points, the top scorer comes first and the groups go.
    await tester.tap(find.text('PTS'));
    await tester.pumpAndSettle();
    expect(find.text('STARTERS'), findsNothing);
    final lavine = tester.getTopLeft(find.text('Z. LaVine')).dy;
    final sabonis = tester.getTopLeft(find.text('D. Sabonis')).dy;
    expect(lavine, lessThan(sabonis));

    // A player's whole line.
    await tester.tap(find.text('D. Sabonis'));
    await tester.pumpAndSettle();
    expect(find.text('Domantas Sabonis'), findsOneWidget);
    expect(find.text('8-13'), findsWidgets);
  });

  testWidgets('a football match has no Players tab', (tester) async {
    final store = (await tester.runAsync(seededStore))!;
    final match = Match(
      id: '401877960',
      league: const League('col.1', 'Primera A'),
      kickoff: DateTime.utc(2026, 10, 6),
      home: const Team('Independiente Medellín', 'Medellín', null, '0'),
      away: const Team('Independiente Santa Fe', 'Santa Fe', null, '1'),
      state: MatchState.finished,
      detail: 'FT',
    );
    await tester.pumpWidget(MaterialApp(
      theme: BankTrackApp.theme('olive'),
      home: MatchPage(match: match, store: store, api: FixturesApi(client: _fixturesClient())),
    ));
    await settle(tester);
    expect(find.widgetWithText(Tab, 'Players'), findsNothing);
    expect(find.widgetWithText(Tab, 'Stats'), findsOneWidget);
  });
}

void _parlayPickTest() {
  testWidgets('picking for a parlay: a tapped match opens the markets, never a single bet', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(seededStore))!;
    MatchesScreen.debugToday = DateTime(2026, 10, 18);
    addTearDown(() => MatchesScreen.debugToday = null);
    final picks = <(String, String, double)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MatchesTabs(
          store: store,
          api: FixturesApi(client: _fixturesClient()),
          today: DateTime(2026, 10, 18),
          onPick: (m, sel, odds) => picks.add((m.id, sel, odds)),
        ),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('AFC Bournemouth').first);
    await tester.pumpAndSettle();
    expect(find.text('Choose a market'), findsOneWidget);
    expect(find.text('Log a bet'), findsNothing);
    // Match result is priced: the odds are already in.
    expect(find.widgetWithText(FilledButton, 'Add to parlay'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Odds')).controller!.text, '2.10');
    // A handicap has no price in the feed: typed by hand.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Handicap'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Odds')).controller!.text, '');
    await tester.enterText(find.widgetWithText(TextField, 'Odds'), '1.85');
    await tester.pumpAndSettle();
    expect(find.text('Settles by itself from the final score.'), findsOneWidget);
    final add = find.widgetWithText(FilledButton, 'Add to parlay');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(picks.single.$2, 'AFC Bournemouth -0.5');
    expect(picks.single.$3, 1.85);
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
http.Response _summary(Uri url) {
  // A game from Everton's or Chelsea's schedule: a box score made from its id.
  final id = url.queryParameters['event'] ?? '';
  final past = RegExp(r'^(20\d\d)(368|363)(\d)$').firstMatch(id);
  if (past != null) {
    final season = int.parse(past[1]!), team = past[2]!, i = int.parse(past[3]!);
    final meets = season < 2026 ? i < 2 : i == 0;
    final opponent = meets ? (team == '368' ? '363' : '368') : '${900 + i}';
    final (h, a) = i.isEven ? (team, opponent) : (opponent, team);
    return http.Response(
      boxSummary(homeId: h, awayId: a, hs: 2, as: i % 3, stats: {
        'wonCorners': (4 + i, 3 + (i * 2) % 5),
        'yellowCards': (1 + i % 3, 2),
        'totalShots': (12 + i, 9 + i),
        'shotsOnTarget': (5, 3 + i % 3),
        'foulsCommitted': (10 + i, 12 - i),
      }),
      200,
    );
  }
  return _summaryFile(url);
}

http.Response _summaryFile(Uri url) => http.Response.bytes(
      File(switch (url.queryParameters['event']) {
        '401878771' => 'test/data/espn_summary_pre.json',
        '401879260' => 'test/data/espn_summary_shots.json',
        '401841641' => 'test/data/espn_summary_arg_zones.json',
        '401809997' => 'test/data/espn_nba_summary_box.json',
        _ => 'test/data/espn_summary_col.json',
      })
          .readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// ESPN team schedules. Everton (368) and Chelsea (363) play six games a
/// season, meeting once this season and twice in each of the five before.
http.Response _schedule(Uri url) {
  final team = url.pathSegments[url.pathSegments.length - 2];
  final season = int.tryParse(url.queryParameters['season'] ?? '') ?? 2026;
  if (team != '368' && team != '363') return http.Response(jsonEncode({'events': []}), 200);
  final other = team == '368' ? '363' : '368';
  final names = {'368': 'Everton', '363': 'Chelsea'};
  final events = [
    for (var i = 0; i < 6; i++)
      () {
        final meets = season < 2026 ? i < 2 : i == 0;
        final opponent = meets ? other : '${900 + i}';
        final home = i.isEven;
        final (h, a) = home ? (team, opponent) : (opponent, team);
        final n = (2026 - season) * 6 + i + 1;
        return {
          'id': '$season$team$i',
          'date': DateTime.utc(season, 10, 12).subtract(Duration(days: 7 * i)).toIso8601String(),
          'league': {'shortName': 'Premier League'},
          'competitions': [
            {
              'status': {'type': {'state': 'post'}},
              'competitors': [
                for (final (side, id, score) in [('home', h, 2), ('away', a, i % 3)])
                  {'homeAway': side, 'team': {'id': id, 'displayName': names[id] ?? 'Opponent ${meets ? 0 : n}'}, 'score': {'displayValue': '$score'}},
              ],
            },
          ],
        };
      }(),
  ];
  return http.Response(jsonEncode({'requestedSeason': {'year': season}, 'events': events}), 200);
}

http.Client _fixturesClient() => MockClient((req) async {
  if (req.url.pathSegments.last == 'summary') return _summary(req.url);
  if (req.url.pathSegments.last == 'schedule') return _schedule(req.url);
  final slug = req.url.pathSegments[req.url.pathSegments.length - 2];
  if (slug == 'all') {
    // Every football league's board, used by the Live tab.
    return http.Response(
      board([
        {
          ...espnEvent(
            '2',
            '2026-10-18T14:00:00Z',
            'Arsenal',
            'Tottenham Hotspur',
            state: 'in',
            detail: "67'",
            hs: '2',
            as: '1',
          ),
          'uid': 's:600~l:700~e:2',
        },
        {
          ...espnEvent(
            '9',
            '2026-10-18T14:00:00Z',
            'Real Madrid',
            'Getafe',
            state: 'in',
            detail: "12'",
            hs: '0',
            as: '0',
          ),
          'uid': 's:600~l:740~e:9',
        },
      ]),
      200,
    );
  }
  if (!req.url.queryParameters.containsKey('dates')) {
    // Today's scoreboard of one league.
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

/// Firebase sign-in and the community server, as the community test needs them.
class _CommunityServer {
  final created = <String>[];
  final taken = {'goalmachine'};

  http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        if (path == '/v1/accounts:signInWithPassword') {
          return _json({'localId': 'uid-1', 'email': 'laura@example.com', 'idToken': 'id:uid-1', 'refreshToken': 'rt:uid-1', 'expiresIn': '3600'});
        }
        if (path == '/v1/token') return _json({'id_token': 'id:uid-1', 'refresh_token': 'rt:uid-1', 'expires_in': '3600'});
        if (req.headers['Authorization'] != 'Bearer id:uid-1') return http.Response('', 401);
        if (path == '/api/me') return _json({'error': 'Create your community profile first.'}, 404);
        if (path == '/api/profiles/available') {
          final h = req.url.queryParameters['handle']!.replaceFirst('@', '').toLowerCase();
          return _json({'handle': h, 'available': !taken.contains(h) && !created.contains(h)});
        }
        if (path == '/api/profiles' && req.method == 'POST') {
          final h = (jsonDecode(req.body) as Map)['handle'] as String;
          if (taken.contains(h)) return _json({'error': 'That username is taken.'}, 409);
          created.add(h);
          return _json({'profile': {'handle': h}, 'tokens': 10}, 201);
        }
        return http.Response('not found', 404);
      });
}
