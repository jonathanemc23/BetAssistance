import 'dart:io';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/logic/community.dart';
import 'package:bank_track/logic/pro_tips.dart';
import 'package:bank_track/logic/purchased.dart';
import 'package:bank_track/ui/bets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final kickoff = DateTime.utc(2026, 10, 20, 19);

Match match(String id, String home, String away) => Match(
      id: id,
      league: const League('eng.1', 'Premier League'),
      kickoff: kickoff,
      home: Team(home, home, null, null),
      away: Team(away, away, null, null),
      state: MatchState.scheduled,
      detail: '',
    );

Tip tip(String matchId, TipMarket market, String pick, Confidence level) => Tip(
    matchId: matchId, legs: [TipLeg(market, pick, 2.0)], chance: 0.5, reasons: const [], free: false, level: level);

void main() {
  sqfliteFfiInit();

  Future<BankStore> newStore() async {
    final store = BankStore(await AppDatabase.open(
        factory: databaseFactoryFfi, path: '${Directory.systemTemp.createTempSync('bought').path}/bank.db'));
    await store.load();
    await store.addTokens(20);
    return store;
  }

  test('bought Pro tips and Community bets list apart, with won vs lost', () async {
    final store = await newStore();
    final m1 = match('701', 'Arsenal', 'Chelsea'), m2 = match('702', 'Leeds', 'Everton');
    final a = tip('701', TipMarket.homeWin, 'Arsenal to win', Confidence.high);
    final b = tip('702', TipMarket.awayWin, 'Everton to win', Confidence.max);
    await store.unlockTip(a, match: m1);
    await store.unlockTip(b, match: m2);
    await store.buyListing(Listing(
        seller: demoSellers.first,
        bet: CommunityBet.on(m1, const TipLeg(TipMarket.over25, 'Over 2.5 goals', 1.9), placed: 'x'),
        price: 2));

    await store.settleTipsOn('701', 2, 0); // a wins
    await store.settleTipsOn('702', 1, 0); // b loses, tokens back
    await store.settleCommunity('701', 2, 0); // over 2.5 loses

    List<PurchasedBet> of(PurchaseSource s) =>
        purchasedBets(s, tips: store.unlockedTips, listings: store.boughtListings);
    final pro = of(PurchaseSource.pro);
    expect(pro.map((p) => p.matchTitle), containsAll(['Arsenal vs Chelsea', 'Leeds vs Everton']));
    final t = PurchaseTally.of(pro);
    expect((t.won, t.lost, t.open), (1, 1, 0));
    expect(t.winRate, 0.5);

    final community = of(PurchaseSource.community);
    expect(community.single.seller, demoSellers.first.handle);
    expect(PurchaseTally.of(community).lost, 1);

    // The match stays with the tip after a restart.
    await store.load();
    expect(store.unlockedTips[a.id]!.match!.title, 'Arsenal vs Chelsea');
  });

  testWidgets('the register shows a Bought section with Pro and Community charts', (tester) async {
    late BankStore store;
    await tester.runAsync(() async {
      store = await newStore();
      await store.unlockTip(tip('701', TipMarket.homeWin, 'Arsenal to win', Confidence.high),
          match: match('701', 'Arsenal', 'Chelsea'));
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: store,
          builder: (_, _) => BetsScreen(store: store, api: FixturesApi()),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('bet-filter-bought')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bought-pro')), findsOneWidget);
    expect(find.byKey(const Key('bought-community')), findsOneWidget);
    expect(find.text('Arsenal to win'), findsOneWidget);
    expect(find.textContaining('Arsenal vs Chelsea'), findsOneWidget);
  });
}
