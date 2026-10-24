import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/store.dart';
import 'package:bank_track/logic/pro_tips.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Match match({String id = '401841641', MatchOdds? odds}) => Match(
      id: id,
      league: const League('arg.1', 'Liga Profesional'),
      kickoff: DateTime.utc(2026, 10, 24, 17, 45),
      home: const Team('Banfield', 'BAN', null, null),
      away: const Team('Lanús', 'LAN', null, null),
      state: MatchState.scheduled,
      detail: '',
      odds: odds,
    );

void main() {
  sqfliteFfiInit();

  test('confidence sets the price: max 3, high 2, medium 1', () {
    expect(Confidence.of(0.8), Confidence.max);
    expect(Confidence.of(0.7), Confidence.high);
    expect(Confidence.of(0.5), Confidence.medium);
    expect([for (final c in Confidence.values) c.cost], [3, 2, 1]);
  });

  test('simulated tips are the same on every visit and never contradict each other', () {
    final m = match(odds: const MatchOdds(home: 2.1, draw: 3.2, away: 3.6));
    final a = simulateTips(m, const MatchDetails()), b = simulateTips(m, const MatchDetails());
    expect(a.all.map((t) => t.id), b.all.map((t) => t.id));
    expect(a.daily, hasLength(2));
    expect(a.pro, hasLength(3));
    expect(a.daily.every((t) => t.free), isTrue);
    expect(a.pro.any((t) => t.free), isFalse);
    final markets = a.all.map((t) => t.market).toSet();
    expect(markets, hasLength(a.all.length));
    expect(markets.containsAll([TipMarket.over25, TipMarket.under25]), isFalse);
    expect(markets.containsAll([TipMarket.bttsYes, TipMarket.bttsNo]), isFalse);
    expect(a.pro.first.confidence, Confidence.max);
  });

  test('tips settle from the final score', () {
    expect(TipMarket.over25.wins(2, 1), isTrue);
    expect(TipMarket.bttsYes.wins(1, 0), isFalse);
    expect(TipMarket.homeOrDraw.wins(1, 1), isTrue);
    expect(TipMarket.overLine.wins(110, 105, line: 214.5), isTrue);
  });

  test('unlocking spends tokens and a lost tip refunds them once', () async {
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final store = BankStore(db);
    await store.load();
    expect(store.tokens, BankStore.starterTokens);
    final tips = simulateTips(match(), const MatchDetails()).pro;
    final t = tips.first;
    expect(await store.unlockTip(t), isTrue);
    expect(store.tokens, BankStore.starterTokens - t.cost);
    expect(store.isUnlocked(t), isTrue);

    // A score where the tip loses.
    (int, int) losing() {
      for (var h = 0; h < 6; h++) {
        for (var a = 0; a < 6; a++) {
          if (t.result(h, a) == false) return (h, a);
        }
      }
      throw StateError('no losing score');
    }

    final (h, a) = losing();
    await store.settleTips(tips, h, a);
    expect(store.tokens, BankStore.starterTokens);
    expect(store.unlockedTips[t.id]!.result, 'refunded');
    await store.settleTips(tips, h, a);
    expect(store.tokens, BankStore.starterTokens);

    // It all survives a restart.
    await store.load();
    expect(store.tokens, BankStore.starterTokens);
    expect(store.unlockedTips[t.id]!.result, 'refunded');
  });

  test('not enough tokens: nothing is spent', () async {
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final store = BankStore(db);
    await store.load();
    await store.addTokens(-store.tokens);
    final t = simulateTips(match(id: 'other'), const MatchDetails()).pro.first;
    expect(await store.unlockTip(t), isFalse);
    expect(store.tokens, 0);
    expect(store.isUnlocked(t), isFalse);
  });
}
