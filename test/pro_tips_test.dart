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
    expect(Confidence.of(0.65), Confidence.max);
    expect(Confidence.of(0.55), Confidence.high);
    expect(Confidence.of(0.45), Confidence.medium);
    expect([for (final c in Confidence.values) c.cost], [3, 2, 1]);
    expect([for (final c in Confidence.values) c.minOdds], [1.8, 1.6, 1.6]);
  });

  test('every tip follows the odds rules and is a value bet', () {
    final books = <MatchOdds?>[
      null,
      const MatchOdds(home: 2.1, draw: 3.2, away: 3.6),
      const MatchOdds(home: 1.25, draw: 6.0, away: 11.0, totalLine: 2.5, over: 1.55, under: 2.45),
      const MatchOdds(home: 4.5, draw: 3.6, away: 1.8),
      const MatchOdds(home: 2.6, draw: 2.9, away: 2.9, totalLine: 2.5, over: 2.2, under: 1.68),
    ];
    var pro = 0, combos = 0, free = 0;
    for (var i = 0; i < 60; i++) {
      final tips = simulateTips(match(id: '40184${1000 + i}', odds: books[i % books.length]), const MatchDetails());
      for (final t in tips.pro) {
        expect(followsOddsRules(t), isTrue, reason: '${t.pick} at ${t.odds}');
        expect(t.free, isFalse);
        expect(t.odds, inInclusiveRange(t.level.minOdds, 2.0), reason: '${t.level} ${t.pick}');
        if (t.level == Confidence.max) expect(t.odds, greaterThanOrEqualTo(1.8));
        if (t.isCombo) {
          expect(t.legs, hasLength(2));
          combos++;
        }
        expect(t.value, greaterThan(0), reason: '${t.pick} at ${t.odds}');
        pro++;
      }
      for (final t in tips.daily) {
        expect(t.odds, inInclusiveRange(1.4, 2.0), reason: t.pick);
        expect(t.isCombo, isFalse);
        free++;
      }
    }
    expect(pro, greaterThan(120));
    expect(combos, greaterThan(20));
    expect(free, greaterThan(80));
  });

  test('the price range follows what the tip costs', () {
    Tip tip(List<TipLeg> legs, {bool free = false, Confidence level = Confidence.max}) =>
        Tip(matchId: '1', legs: legs, chance: 0.6, reasons: const [], free: free, level: level);
    const short = TipLeg(TipMarket.homeWin, 'Home', 1.75), mid = TipLeg(TipMarket.over25, 'Over', 1.85);
    const long = TipLeg(TipMarket.draw, 'Draw', 2.2), low = TipLeg(TipMarket.homeWin, 'Home', 1.5);
    // Max (3 tokens): 1.80 to 2.00.
    expect(followsOddsRules(tip([short])), isFalse);
    expect(followsOddsRules(tip([mid])), isTrue);
    expect(followsOddsRules(tip([long])), isFalse);
    // High and Medium: 1.60 to 2.00.
    for (final level in [Confidence.high, Confidence.medium]) {
      expect(followsOddsRules(tip([short], level: level)), isTrue);
      expect(followsOddsRules(tip([low], level: level)), isFalse);
      expect(followsOddsRules(tip([long], level: level)), isFalse);
    }
    // Two selections count by their combined odds.
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 1.3), const TipLeg(TipMarket.over15, 'O', 1.45)])),
        isTrue);
    expect(followsOddsRules(tip([short, mid])), isFalse);
    // Free: 1.40 to 2.00.
    expect(followsOddsRules(tip([short], free: true)), isTrue);
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 2.2)], free: true)), isFalse);
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 1.3)], free: true)), isFalse);
  });

  test('a bought tip keeps its place when the prices move', () {
    final before = simulateTips(match(odds: const MatchOdds(home: 2.1, draw: 3.2, away: 3.6)), const MatchDetails());
    final bought = Tip.fromJson(before.pro.first.toJson())!;
    expect(bought.id, before.pro.first.id);
    expect(bought.odds, closeTo(before.pro.first.odds, 1e-9));
    final after = simulateTips(match(odds: const MatchOdds(home: 1.6, draw: 3.9, away: 5.5)), const MatchDetails())
        .withBought([bought]);
    expect(after.pro.where((t) => t.id == bought.id), hasLength(1));
    expect(after.pro.where((t) => t.level == bought.level), hasLength(1));
  });

  test('simulated tips are the same on every visit and never contradict each other', () {
    final m = match(odds: const MatchOdds(home: 2.1, draw: 3.2, away: 3.6));
    final a = simulateTips(m, const MatchDetails()), b = simulateTips(m, const MatchDetails());
    expect(a.all.map((t) => t.id), b.all.map((t) => t.id));
    expect(a.daily, isNotEmpty);
    expect(a.pro, hasLength(3));
    expect(a.daily.every((t) => t.free), isTrue);
    expect(a.pro.any((t) => t.free), isFalse);
    expect(a.all.map((t) => t.id).toSet(), hasLength(a.all.length));
    final markets = {for (final t in a.all) ...t.legs.map((l) => l.market)};
    expect(markets.containsAll([TipMarket.over25, TipMarket.under25]), isFalse);
    expect(markets.containsAll([TipMarket.bttsYes, TipMarket.bttsNo]), isFalse);
    expect(a.pro.map((t) => t.level), [Confidence.max, Confidence.high, Confidence.medium]);
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
