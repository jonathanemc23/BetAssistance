import 'dart:io';

import 'package:bank_track/data/board.dart';
import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/favorites.dart';
import 'package:bank_track/data/fixtures.dart';
import 'package:bank_track/data/models.dart';
import 'package:bank_track/data/parlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('banktrack');
    path = p.join(dir.path, AppDatabase.fileName);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Bet sample() => Bet(
      selection: 'Arsenal to win', event: 'Arsenal vs Chelsea', sport: 'Soccer', date: '2026-10-01',
      stake: 20, odds: 2.1, book: 'Book', status: BetStatus.won, notes: 'n', created: '2026-10-01T10:00:00');

  test('data written by one app launch is there on the next', () async {
    var db = await AppDatabase.open(factory: factory, path: path);
    await db.saveBet(sample());
    await db.saveTx(const BankTx(kind: TxKind.deposit, amount: 100, date: '2026-10-02', note: 'top up'));
    await db.saveSettings(const Settings(currency: 'EUR', startBankroll: 500, startDate: '2026-09-01', unit: 5));
    await db.close();

    db = await AppDatabase.open(factory: factory, path: path);
    final bets = await db.bets();
    expect(bets, hasLength(1));
    expect(bets.single.selection, 'Arsenal to win');
    expect(bets.single.status, BetStatus.won);
    expect((await db.transactions()).single.amount, 100);
    final s = await db.settings();
    expect(s.currency, 'EUR');
    expect(s.startBankroll, 500);
    await db.close();
  });

  test("void status round-trips with the web version's stored value", () async {
    final db = await AppDatabase.open(factory: factory, path: path);
    final id = await db.saveBet(sample().copyWith(status: BetStatus.voided));
    final raw = await db.db.query('bets', where: 'id = ?', whereArgs: [id]);
    expect(raw.single['status'], 'void');
    expect((await db.bets()).single.status, BetStatus.voided);
    await db.close();
  });

  test('a future schema migration keeps existing rows', () async {
    final db = await AppDatabase.open(factory: factory, path: path);
    await db.saveBet(sample());
    await db.close();

    // Simulate the next release adding a column.
    migrations.add((db) => db.execute("ALTER TABLE bets ADD COLUMN tag TEXT NOT NULL DEFAULT ''"));
    try {
      final upgraded = await AppDatabase.open(factory: factory, path: path);
      expect(await upgraded.db.getVersion(), schemaVersion);
      final rows = await upgraded.db.query('bets');
      expect(rows.single['selection'], 'Arsenal to win');
      expect(rows.single['tag'], '');
      await upgraded.close();
    } finally {
      migrations.removeLast();
    }
  });

  test('a failed migration rolls back and leaves the data intact', () async {
    final db = await AppDatabase.open(factory: factory, path: path);
    await db.saveBet(sample());
    await db.close();

    migrations.add((db) async {
      await db.execute('ALTER TABLE bets ADD COLUMN tag TEXT');
      throw StateError('boom');
    });
    try {
      await expectLater(AppDatabase.open(factory: factory, path: path), throwsA(anything));
    } finally {
      migrations.removeLast();
    }
    final again = await factory.openDatabase(path);
    expect(await again.getVersion(), schemaVersion);
    expect(await again.query('bets'), hasLength(1));
    final cols = await again.rawQuery('PRAGMA table_info(bets)');
    expect(cols.any((c) => c['name'] == 'tag'), isFalse);
    await again.close();
  });

  test('upgrading from the first release (v1) keeps bets and makes them singles', () async {
    // Build a database exactly as release 0.1.0 left it.
    final old = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => migrations[0](db)));
    await old.insert('bets', {
      'selection': 'Arsenal to win', 'sport': 'Soccer', 'date': '2026-10-01', 'stake': 20, 'odds': 2.1,
      'status': 'won', 'created': '2026-10-01T10:00:00',
    });
    await old.insert('transactions', {'kind': 'deposit', 'amount': 50, 'date': '2026-10-02'});
    await old.insert('settings', {'key': 'currency', 'value': 'EUR'});
    await old.close();

    final db = await AppDatabase.open(factory: factory, path: path);
    expect(await db.db.getVersion(), schemaVersion);
    final bets = await db.bets();
    expect(bets.single.selection, 'Arsenal to win');
    expect(bets.single.type, BetType.single);
    expect(bets.single.legs, isEmpty);
    expect(bets.single.profit, closeTo(22, 1e-9));
    expect((await db.transactions()).single.amount, 50);
    expect((await db.settings()).currency, 'EUR');
    await db.close();
  });

  test('parlay legs are saved, replaced on edit and removed with the bet', () async {
    final db = await AppDatabase.open(factory: factory, path: path);
    final parlay = Bet(
      type: BetType.parlay, selection: '2-leg parlay', date: '2026-10-01', stake: 10, odds: 3, created: 'x',
      legs: const [BetLeg(selection: 'A', odds: 1.5), BetLeg(selection: 'B', odds: 2, sport: 'Tennis')],
    );
    final id = await db.saveBet(parlay);
    var saved = (await db.bets()).single;
    expect(saved.type, BetType.parlay);
    expect(saved.legs.map((l) => l.selection), ['A', 'B']);
    expect(saved.legs.last.sport, 'Tennis');

    await db.saveBet(Bet(
      id: id, type: BetType.parlay, selection: '3-leg parlay', date: '2026-10-01', stake: 10, odds: 6, created: 'x',
      legs: const [
        BetLeg(selection: 'A', odds: 1.5, status: BetStatus.won),
        BetLeg(selection: 'B', odds: 2),
        BetLeg(selection: 'C', odds: 2),
      ],
    ));
    saved = (await db.bets()).single;
    expect(saved.legs, hasLength(3));
    expect(saved.legs.first.status, BetStatus.won);

    await db.deleteBet(id);
    expect(await db.bets(), isEmpty);
    expect(await db.db.query('bet_legs'), isEmpty);
    await db.close();
  });

  test('an older app refuses a newer database instead of wiping it', () async {
    final raw = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => migrations[0](db)));
    await raw.insert('settings', {'key': 'currency', 'value': 'GBP'});
    await raw.setVersion(99);
    await raw.close();
    await expectLater(AppDatabase.open(factory: factory, path: path), throwsA(anything));
    final check = await factory.openDatabase(path);
    expect(await check.getVersion(), 99);
    expect(await check.query('settings'), hasLength(1));
    await check.close();
  });

  test('upgrading from 0.5.0 (v2) keeps bets and settings and adds Matchboard', () async {
    final old = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 2, onCreate: (db, _) async {
          await migrations[0](db);
          await migrations[1](db);
        }));
    await old.insert('bets', {
      'selection': '2-leg parlay', 'sport': 'Soccer', 'date': '2026-10-01', 'stake': 10, 'odds': 3.0,
      'status': 'pending', 'created': '2026-10-01T10:00:00', 'bet_type': 'parlay',
    });
    await old.insert('settings', {'key': 'pref.matches.country', 'value': 'col'});
    await old.close();

    final db = await AppDatabase.open(factory: factory, path: path);
    expect(await db.db.getVersion(), schemaVersion);
    expect((await db.bets()).single.type, BetType.parlay);
    expect(await db.pref('matches.country'), 'col');
    expect(await db.boards(), isEmpty);
    await db.close();
  });

  test('a board keeps its chat and notes, one board per match', () async {
    final db = await AppDatabase.open(factory: factory, path: path);
    final draft = Board(
      matchId: '401878771', leagueSlug: 'eng.1', leagueName: 'Premier League', home: 'Everton', away: 'Chelsea',
      kickoff: DateTime.utc(2026, 10, 18, 19), created: '2026-10-17T10:00:00', updated: '2026-10-17T10:00:00',
    );
    final b = await db.boardFor(draft);
    expect((await db.boardFor(draft)).id, b.id); // opening it again reuses it
    await db.addMessage(BoardMessage(boardId: b.id!, role: ChatRole.user, text: 'Who wins?', created: 'x'));
    await db.addMessage(BoardMessage(boardId: b.id!, role: ChatRole.assistant, text: 'Chelsea', created: 'x'));
    final first = await db.addNote(BoardNote(boardId: b.id!, category: 'Summary', title: 'Match summary', body: 'Chelsea', created: '2026-10-17T10:01:00'));
    await db.addNote(BoardNote(boardId: b.id!, category: 'My notes', title: 'Keeper back', body: 'Keeper back', source: 'user', created: '2026-10-17T10:02:00'));
    await db.setNotePinned(first, true);

    final notes = await db.notes(b.id!);
    expect(notes.first.title, 'Match summary'); // pinned first
    expect(notes.first.pinned, isTrue);
    expect((await db.messages(b.id!)).map((m) => m.role), [ChatRole.user, ChatRole.assistant]);
    final listed = (await db.boards()).single;
    expect(listed.noteCount, 2);
    expect(listed.lastNote, 'Keeper back');
    expect(listed.kickoff, DateTime.utc(2026, 10, 18, 19));

    await db.deleteBoard(b.id!);
    expect(await db.boards(), isEmpty);
    expect(await db.notes(b.id!), isEmpty);
    expect(await db.messages(b.id!), isEmpty);
    await db.close();
  });

  test('upgrading from 0.6.0 (v3) keeps bets and boards and adds the parlay builder', () async {
    final old = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 3, onCreate: (db, _) async {
          for (var v = 0; v < 3; v++) {
            await migrations[v](db);
          }
        }));
    await old.insert('bets', {
      'selection': 'Arsenal to win', 'sport': 'Soccer', 'date': '2026-10-01', 'stake': 10, 'odds': 2.0,
      'status': 'won', 'created': '2026-10-01T10:00:00', 'bet_type': 'single',
    });
    await old.insert('boards', {
      'match_id': '1', 'league_slug': 'eng.1', 'home': 'Everton', 'away': 'Chelsea',
      'kickoff': '2026-10-18T19:00:00Z', 'created': 'x', 'updated': 'x',
    });
    await old.insert('settings', {'key': 'pref.app.theme', 'value': 'ember'});
    await old.close();

    final db = await AppDatabase.open(factory: factory, path: path);
    expect(await db.db.getVersion(), schemaVersion);
    expect((await db.bets()).single.status, BetStatus.won);
    expect((await db.boards()).single.home, 'Everton');
    expect(await db.pref('app.theme'), 'ember');
    expect(await db.parlays(), isEmpty);
    await db.close();
  });

  test('a parlay keeps its legs, linked match, check and result', () async {
    var db = await AppDatabase.open(factory: factory, path: path);
    final id = await db.saveParlay(Parlay(
      name: 'Saturday',
      stake: 10,
      created: 'x',
      updated: 'x',
      legs: [
        ParlayLeg(
          selection: 'Chelsea to win', event: 'Everton vs Chelsea', odds: 2.2, matchId: '401878771',
          leagueSlug: 'eng.1', leagueName: 'Premier League', home: 'Everton', away: 'Chelsea',
          kickoff: DateTime.utc(2026, 10, 18, 19),
        ),
        const ParlayLeg(selection: 'Millonarios to win', event: 'Millonarios vs Nacional', odds: 2.0),
      ],
      check: const ParlayCheck(checked: '2026-10-17T10:00:00', risk: 'Medium', summary: ['ok'], legs: [
        LegCheck(selection: 'Chelsea to win', verdict: 'Fair price', tone: LegTone.neutral, lines: ['a']),
      ]),
    ));
    await db.close();

    db = await AppDatabase.open(factory: factory, path: path);
    var p = (await db.parlays()).single;
    expect(p.id, id);
    expect(p.odds, closeTo(4.4, 1e-9));
    expect(p.potentialReturn, closeTo(44, 1e-9));
    expect(p.legs.first.isLinked, isTrue);
    expect(p.legs.first.toMatch()!.home.name, 'Everton');
    expect(p.legs.last.isLinked, isFalse);
    expect(p.check!.risk, 'Medium');
    expect(p.check!.legs.single.tone, LegTone.neutral);

    // Editing replaces the legs; the result is kept.
    await db.saveParlay(p.copyWith(legs: [p.legs.first.copyWith(status: BetStatus.won)], status: BetStatus.won));
    p = (await db.parlays()).single;
    expect(p.legs.single.status, BetStatus.won);
    expect(p.status, BetStatus.won);
    final bet = p.toBet(date: '2026-10-17', created: 'x');
    expect(bet.type, BetType.parlay);
    expect(bet.legs.single.status, BetStatus.pending);

    await db.deleteParlay(id);
    expect(await db.parlays(), isEmpty);
    expect(await db.db.query('parlay_legs'), isEmpty);
    await db.close();
  });

  test('upgrading from 0.7.0 (v4) keeps bets and parlays and adds markets', () async {
    final old = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 4, onCreate: (db, _) async {
          for (var v = 0; v < 4; v++) {
            await migrations[v](db);
          }
        }));
    await old.insert('bets', {
      'selection': 'Liverpool -1.5', 'sport': 'Soccer', 'date': '2026-10-01', 'stake': 10, 'odds': 2.0,
      'status': 'won', 'created': '2026-10-01T10:00:00', 'bet_type': 'single',
    });
    await old.insert('parlays', {'name': 'Saturday', 'created': 'x', 'updated': 'x'});
    await old.close();

    final db = await AppDatabase.open(factory: factory, path: path);
    expect(await db.db.getVersion(), schemaVersion);
    final bet = (await db.bets()).single;
    expect(bet.selection, 'Liverpool -1.5');
    expect(bet.market, '');
    expect(bet.matchId, isNull);
    expect((await db.parlays()).single.name, 'Saturday');

    // The new fields round-trip.
    await db.saveBet(Bet(
      selection: 'Chelsea -0.5', event: 'Everton vs Chelsea', sport: 'Soccer', date: '2026-10-18', stake: 10,
      odds: 1.95, created: 'y', market: 'handicap', matchId: '401878771', leagueSlug: 'eng.1',
      leagueName: 'Premier League', kickoff: DateTime.utc(2026, 10, 18, 19),
    ));
    final saved = (await db.bets()).firstWhere((b) => b.created == 'y');
    expect(saved.market, 'handicap');
    expect(saved.matchId, '401878771');
    expect(saved.kickoff, DateTime.utc(2026, 10, 18, 19));
    expect(saved.copyWith(status: BetStatus.won).leagueSlug, 'eng.1');
    await db.close();
  });

  test('upgrading from 0.8.0 (v5) keeps everything and adds favourites', () async {
    final old = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 5, onCreate: (db, _) async {
          for (var v = 0; v < 5; v++) {
            await migrations[v](db);
          }
        }));
    await old.insert('bets', {
      'selection': 'Chelsea -0.5', 'sport': 'Soccer', 'date': '2026-10-18', 'stake': 10, 'odds': 1.95,
      'status': 'pending', 'created': 'z', 'bet_type': 'single', 'market': 'handicap', 'match_id': '401878771',
    });
    await old.insert('parlays', {'name': 'Sunday', 'created': 'x', 'updated': 'x'});
    await old.close();

    final db = await AppDatabase.open(factory: factory, path: path);
    expect(await db.db.getVersion(), schemaVersion);
    expect((await db.bets()).single.market, 'handicap');
    expect((await db.parlays()).single.name, 'Sunday');
    expect(await db.favorites(), isEmpty);

    final m = Match(
      id: 'tsdb:7',
      league: leagueBySlug('tsdb.5831')!,
      kickoff: DateTime.utc(2026, 10, 18, 16),
      home: const Team('Beerschot', 'Beerschot', null, null),
      away: const Team('Anderlecht', 'Anderlecht', 'https://x/a.png', null),
      state: MatchState.scheduled,
      detail: '',
    );
    await db.saveFavorite(FavoriteMatch.fromMatch(m, 'now'));
    await db.saveFavorite(FavoriteMatch.fromMatch(m, 'again')); // starring twice keeps one
    final f = (await db.favorites()).single;
    expect((f.matchId, f.home, f.awayLogo, f.kickoff, f.added), ('tsdb:7', 'Beerschot', 'https://x/a.png', m.kickoff, 'again'));
    expect(f.toMatch().league.tsdb, 5831);
    await db.deleteFavorite('tsdb:7');
    expect(await db.favorites(), isEmpty);
    await db.close();
  });
}
