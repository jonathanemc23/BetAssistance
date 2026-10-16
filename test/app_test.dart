import 'dart:io';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await db.saveBet(Bet(
        date: r.$1, sport: r.$2, event: r.$3, selection: r.$4, stake: r.$5, odds: r.$6, status: r.$7,
        cashout: r.$8, created: '${r.$1}T12:00:00'));
  }
  await db.saveTx(const BankTx(kind: TxKind.deposit, amount: 200, date: '2026-08-01', note: 'Top up'));
  final store = BankStore(db);
  await store.load();
  return store;
}

void main() {
  sqfliteFfiInit();
  final shots = Platform.environment['SCREENSHOTS'] == '1';

  testWidgets('both screens render with data and a bet can be settled', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    if (shots) await tester.runAsync(loadFonts);

    final store = (await tester.runAsync(seededStore))!;
    await tester.pumpWidget(BankTrackApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('BANKROLL'), findsOneWidget);
    expect(find.text('ROI'), findsOneWidget);
    expect(find.text('WIN RATE'), findsOneWidget);
    expect(find.text('Bet register'), findsOneWidget);
    if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/bets.png'));

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

    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(find.text('Bankroll over time'), findsOneWidget);
    expect(find.text('Profit by month'), findsOneWidget);
    if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/charts.png'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Profit by sport'), findsOneWidget);
    if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/charts_2.png'));

    await tester.tap(find.text('Bets'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/bets_list.png'));
    await tester.tap(find.text('Log bet'));
    await tester.pumpAndSettle();
    expect(find.text('Log a bet'), findsOneWidget);
    if (shots) await expectLater(find.byType(BankTrackApp), matchesGoldenFile('screenshots/log_bet.png'));
  });
}
