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

const proLevelsForTest = [Confidence.max, Confidence.high];

void main() {
  sqfliteFfiInit();

  test('confidence sets the price: max 3, high 2; Pro tips start at 1.80', () {
    expect(Confidence.of(0.65), Confidence.high);
    expect(Confidence.of(0.55), Confidence.medium);
    expect([for (final c in Confidence.values) c.cost], [3, 2, 1]);
    expect([for (final c in Confidence.values) c.minOdds], [1.8, 1.8, 1.8]);
  });

  test('tips come only from real prices: chance is the price without its margin', () {
    // No bookmaker price: no tips at all, nothing estimated.
    final none = pickTips(match(), const MatchDetails());
    expect(none.all, isEmpty);
    expect(pricedMarkets(match(), const MatchDetails()), isEmpty);

    const book = MatchOdds(home: 1.9, draw: 3.4, away: 4.2, totalLine: 2.5, over: 1.95, under: 1.85);
    final priced = pricedMarkets(match(odds: book), const MatchDetails());
    expect({for (final c in priced) c.leg.market},
        {TipMarket.homeWin, TipMarket.draw, TipMarket.awayWin, TipMarket.over25, TipMarket.under25});
    final home = priced.firstWhere((c) => c.leg.market == TipMarket.homeWin);
    expect(home.leg.odds, 1.9);
    final sum = 1 / 1.9 + 1 / 3.4 + 1 / 4.2;
    expect(home.chance, closeTo((1 / 1.9) / sum, 1e-9));
    for (final c in priced) {
      expect(c.chance, lessThan(1 / c.leg.odds), reason: 'the margin is taken out');
    }

    // Every market stays on the list; the unpriced ones carry no odds.
    final all = matchMarkets(match(odds: book), const MatchDetails());
    expect(all.firstWhere((o) => o.market == TipMarket.bttsYes).odds, isNull);
    expect(all.firstWhere((o) => o.market == TipMarket.over25).odds, 1.95);
  });

  test('Pro tips: High or Max singles at real odds of 1.80 to 2.00; free tips 1.40 to 2.00', () {
    final books = <MatchOdds>[
      const MatchOdds(home: 1.9, draw: 3.4, away: 4.2, totalLine: 2.5, over: 1.95, under: 1.85),
      const MatchOdds(home: 2.1, draw: 3.2, away: 3.6),
      const MatchOdds(home: 1.25, draw: 6.0, away: 11.0, totalLine: 2.5, over: 1.55, under: 2.45),
      const MatchOdds(home: 4.5, draw: 3.6, away: 1.8),
      const MatchOdds(home: 2.6, draw: 2.9, away: 2.9, totalLine: 2.5, over: 2.2, under: 1.68),
    ];
    var pro = 0, free = 0;
    for (final b in books) {
      final tips = pickTips(match(odds: b), const MatchDetails());
      for (final t in tips.pro) {
        expect(followsOddsRules(t), isTrue, reason: '${t.pick} at ${t.odds}');
        expect(t.level, isNot(Confidence.medium));
        expect(t.odds, inInclusiveRange(1.8, 2.0));
        expect(t.chance, greaterThanOrEqualTo(0.44));
        if (t.level == Confidence.max) expect(t.chance, greaterThanOrEqualTo(0.5));
        expect(t.isCombo, isFalse);
        pro++;
      }
      for (final t in tips.daily) {
        expect(followsOddsRules(t), isTrue, reason: t.pick);
        expect(t.level, isNot(Confidence.max));
        free++;
      }
      // Never two tips that can't both win.
      final legs = [for (final t in tips.all) t.legs.single];
      for (var i = 0; i < legs.length; i++) {
        for (var j = i + 1; j < legs.length; j++) {
          final (x, y) = (legs[i].market, legs[j].market);
          var both = false;
          for (var h = 0; h <= 8; h++) {
            for (var a = 0; a <= 8; a++) {
              if (x.wins(h, a) && y.wins(h, a)) both = true;
            }
          }
          expect(both, isTrue, reason: '$x and $y');
        }
      }
    }
    expect(pro, greaterThan(2));
    expect(free, greaterThan(1));
    // The first book: under 2.5 at 1.85 is the market's 51% pick, so Max.
    final first = pickTips(match(odds: books.first), const MatchDetails());
    expect(first.pro.first.market, TipMarket.under25);
    expect(first.pro.first.level, Confidence.max);
  });

  test('the odds rules', () {
    Tip tip(List<TipLeg> legs, {bool free = false, Confidence level = Confidence.max}) =>
        Tip(matchId: '1', legs: legs, chance: 0.6, reasons: const [], free: free, level: level);
    const short = TipLeg(TipMarket.homeWin, 'Home', 1.75), mid = TipLeg(TipMarket.over25, 'Over', 1.85);
    const long = TipLeg(TipMarket.draw, 'Draw', 2.2);
    for (final level in proLevelsForTest) {
      expect(followsOddsRules(tip([short], level: level)), isFalse);
      expect(followsOddsRules(tip([mid], level: level)), isTrue);
      expect(followsOddsRules(tip([long], level: level)), isFalse);
    }
    expect(followsOddsRules(tip([mid], level: Confidence.medium)), isFalse);
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 1.3), const TipLeg(TipMarket.over15, 'O', 1.45)])),
        isFalse);
    expect(followsOddsRules(tip([short], free: true)), isTrue);
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 2.2)], free: true)), isFalse);
    expect(followsOddsRules(tip([const TipLeg(TipMarket.homeWin, 'Home', 1.3)], free: true)), isFalse);
  });

  test('a bought tip keeps its place when the prices move', () {
    const before0 = MatchOdds(home: 1.9, draw: 3.4, away: 4.2);
    final before = pickTips(match(odds: before0), const MatchDetails());
    final bought = Tip.fromJson(before.pro.first.toJson())!;
    expect(bought.id, before.pro.first.id);
    expect(bought.odds, closeTo(before.pro.first.odds, 1e-9));
    final after = pickTips(match(odds: const MatchOdds(home: 1.6, draw: 3.9, away: 5.5)), const MatchDetails())
        .withBought([bought]);
    expect(after.pro.where((t) => t.id == bought.id), hasLength(1));
  });

  test('tips are the same on every visit', () {
    final m = match(odds: const MatchOdds(home: 1.9, draw: 3.4, away: 4.2, totalLine: 2.5, over: 1.95, under: 1.85));
    final a = pickTips(m, const MatchDetails()), b = pickTips(m, const MatchDetails());
    expect(a.all.map((t) => t.id), b.all.map((t) => t.id));
    expect(a.daily.every((t) => t.free), isTrue);
    expect(a.pro.any((t) => t.free), isFalse);
    expect(a.all.map((t) => t.id).toSet(), hasLength(a.all.length));
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
    final tips = pickTips(match(odds: const MatchOdds(home: 1.9, draw: 3.4, away: 4.2)), const MatchDetails()).pro;
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
    final t = pickTips(match(id: 'other', odds: const MatchOdds(home: 1.9, draw: 3.4, away: 4.2)), const MatchDetails()).pro.first;
    expect(await store.unlockTip(t), isFalse);
    expect(store.tokens, 0);
    expect(store.isUnlocked(t), isFalse);
  });

  test('free picks of the day: the likeliest, one per match, at most 3 and 2 High', () {
    Tip t(String id, double chance, Confidence level) => Tip(
        matchId: id,
        legs: const [TipLeg(TipMarket.homeWin, 'Home', 1.5)],
        chance: chance,
        reasons: const [],
        free: true,
        level: level);
    final picks = freePicksOfTheDay([
      ('a', t('a', 0.70, Confidence.high)),
      ('a', t('a', 0.69, Confidence.high)),
      ('b', t('b', 0.66, Confidence.high)),
      ('c', t('c', 0.64, Confidence.high)),
      ('d', t('d', 0.55, Confidence.medium)),
      ('e', t('e', 0.52, Confidence.medium)),
    ]);
    expect(picks.map((p) => p.$1), ['a', 'b', 'd']);
    expect(freePicksOfTheDay(<(String, Tip)>[]), isEmpty);
  });
}
