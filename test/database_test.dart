import 'dart:io';

import 'package:bank_track/data/database.dart';
import 'package:bank_track/data/models.dart';
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
      expect(await upgraded.db.getVersion(), 2);
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
    expect(await again.getVersion(), 1);
    expect(await again.query('bets'), hasLength(1));
    final cols = await again.rawQuery('PRAGMA table_info(bets)');
    expect(cols.any((c) => c['name'] == 'tag'), isFalse);
    await again.close();
  });

  test('an older app refuses a newer database instead of wiping it', () async {
    final raw = await factory.openDatabase(path,
        options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => migrations[0](db)));
    await raw.insert('settings', {'key': 'currency', 'value': 'GBP'});
    await raw.setVersion(5);
    await raw.close();
    await expectLater(AppDatabase.open(factory: factory, path: path), throwsA(anything));
    final check = await factory.openDatabase(path);
    expect(await check.getVersion(), 5);
    expect(await check.query('settings'), hasLength(1));
    await check.close();
  });
}
