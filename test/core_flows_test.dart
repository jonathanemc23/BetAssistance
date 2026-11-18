// Screens the main app test doesn't reach: deposits and withdrawals,
// settings validation, share links and the preset person avatars.
import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/share.dart';
import 'package:bank_track/ui/bank_screens.dart';
import 'package:bank_track/ui/person_avatar.dart';
import 'package:bank_track/ui/share_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_test.dart' show seededStore;

Widget _app(Widget home) => MaterialApp(home: home);

/// A tall phone screen, so whole forms fit without scrolling.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

/// A [MaterialApp] whose home has one button that runs [action].
Widget _launcher(Future<void> Function(BuildContext) action) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => Center(child: TextButton(onPressed: () => action(c), child: const Text('go'))),
        ),
      ),
    );

void main() {
  sqfliteFfiInit();

  group('deposits and withdrawals', () {
    testWidgets('a deposit needs an amount above zero, then moves the bankroll', (tester) async {
      final store = await tester.runAsync(seededStore);
      _tallScreen(tester);
      await tester.pumpWidget(_app(TransactionsPage(store: store!)));
      final before = store.stats.balance;
      final deposits = store.stats.deposits;

      await tester.tap(find.widgetWithText(FilledButton, 'Deposit'));
      await tester.pumpAndSettle();
      expect(find.text('Add deposit'), findsOneWidget);

      // Zero and words are refused, with the reason under the field.
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above zero'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'abc');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above zero'), findsOneWidget);
      expect(store.txs.length, 1);

      // A comma works as the decimal mark.
      await tester.enterText(find.byType(TextField).first, '150,50');
      await tester.enterText(find.byType(TextField).last, 'Bet365');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Add deposit'), findsNothing);
      expect(store.txs.length, 2);
      expect(store.stats.deposits, closeTo(deposits + 150.5, 0.001));
      expect(store.stats.balance, closeTo(before + 150.5, 0.001));
      expect(find.textContaining('Bet365'), findsOneWidget);
    });

    testWidgets('a withdrawal lowers the bankroll and a swipe deletes it', (tester) async {
      final store = await tester.runAsync(seededStore);
      _tallScreen(tester);
      await tester.pumpWidget(_app(TransactionsPage(store: store!)));
      final before = store.stats.balance;

      await tester.tap(find.widgetWithText(OutlinedButton, 'Withdrawal'));
      await tester.pumpAndSettle();
      expect(find.text('Add withdrawal'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '80');
      await tester.runAsync(() async {
        await tester.tap(find.text('Save'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(store.stats.withdrawals, closeTo(80, 0.001));
      expect(store.stats.balance, closeTo(before - 80, 0.001));

      final tile = find.ancestor(of: find.text('Withdrawal').first, matching: find.byType(Dismissible));
      await tester.runAsync(() async {
        await tester.drag(tile, const Offset(-600, 0));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(store.stats.withdrawals, 0);
      expect(store.stats.balance, closeTo(before, 0.001));
    });
  });

  group('settings', () {
    testWidgets('a typo in the bankroll or the unit is refused instead of saved as 0', (tester) async {
      final store = await tester.runAsync(seededStore);
      _tallScreen(tester);
      await tester.pumpWidget(_app(SettingsPage(store: store!)));
      await tester.pumpAndSettle();

      final start = find.widgetWithText(TextField, 'Starting bankroll');
      final unit = find.widgetWithText(TextField, 'Unit size');
      await tester.scrollUntilVisible(unit, 300, scrollable: find.byType(Scrollable).first);
      await tester.enterText(start, 'mil');
      await tester.enterText(unit, '0');
      await tester.scrollUntilVisible(find.text('Save settings'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Starting bankroll'), -300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Enter a number, 0 or more'), findsOneWidget);
      expect(find.text('Enter an amount above zero'), findsOneWidget);
      expect(store.settings.startBankroll, 1000);
      expect(store.settings.unit, 20);
      expect(find.text('Settings'), findsOneWidget, reason: 'still on the page');
      // Let the page's start-up reads of the database finish.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('valid values, the currency and the odds format are saved', (tester) async {
      final store = await tester.runAsync(seededStore);
      _tallScreen(tester);
      String? result;
      await tester.pumpWidget(_launcher((c) async {
        result = await Navigator.push<String>(c, MaterialPageRoute(builder: (_) => SettingsPage(store: store!)));
      }));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Unit size'), 300, scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.widgetWithText(TextField, 'Starting bankroll'), ' 1500,5 ');
      await tester.enterText(find.widgetWithText(TextField, 'Unit size'), '25');
      await tester.scrollUntilVisible(find.text('Decimal (2.50)'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Decimal (2.50)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('American (+150)').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Save settings'), 300, scrollable: find.byType(Scrollable).first);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save settings'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(result, 'Settings saved');
      expect(store!.settings.startBankroll, 1500.5);
      expect(store.settings.unit, 25);
      expect(store.settings.oddsFormat, OddsFormat.american);
    });
  });

  group('share links', () {
    const bet = Bet(
      date: '2026-11-18',
      sport: 'Basketball',
      event: 'Celtics vs Knicks',
      selection: 'Celtics -4.5',
      stake: 20,
      odds: 1.91,
      created: '2026-11-18T12:00:00',
    );

    testWidgets('the share sheet shows the link and copies it', (tester) async {
      final store = await tester.runAsync(seededStore);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(_launcher((c) => showShareBet(c, store!, bet)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final link = BetLink.webLink(bet);
      expect(find.text('Share this bet'), findsOneWidget);
      expect(find.text(link), findsOneWidget);

      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied, link);
      expect(find.text('Share this bet'), findsNothing);
    });

    testWidgets('pasting a link opens its bet; anything else is refused', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'hello there'};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      Bet? opened;
      var closed = false;
      await tester.pumpWidget(_launcher((c) async {
        opened = await showPasteLink(c);
        closed = true;
      }));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Open a bet link'), findsOneWidget);
      expect(find.text('hello there'), findsOneWidget, reason: 'the clipboard is pasted in');

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text("That doesn't look like a BetPilot bet link"), findsOneWidget);
      expect(closed, isFalse);

      await tester.enterText(find.byType(TextField), 'Look at this: ${BetLink.webLink(bet)}');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(opened?.selection, 'Celtics -4.5');
      expect(opened?.odds, 1.91);
      expect(opened?.stake, 20);
    });
  });

  testWidgets('every preset person avatar draws at small and large sizes', (tester) async {
    await tester.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: Wrap(children: [
          for (final look in personLooks) ...[PersonAvatar(look: look, size: 32), PersonAvatar(look: look, size: 96)],
        ]),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(PersonAvatar), findsNWidgets(personLooks.length * 2));
    expect(tester.takeException(), isNull);
  });
}
