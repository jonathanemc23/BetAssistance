import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Schema migrations, applied in order. Entry N upgrades the schema from
/// version N to N+1, so a phone on any older release is walked forward one
/// step at a time and keeps every row it already has.
///
/// Rules for future releases:
/// - Never edit or remove an existing entry; append a new one.
/// - Only additive or copy-then-swap changes (ALTER TABLE ADD COLUMN, new
///   tables, INSERT INTO new SELECT FROM old). Never DROP user data.
/// - Bump nothing else: [schemaVersion] follows the length of this list.
final List<Future<void> Function(DatabaseExecutor db)> migrations = [
  // 0 -> 1: initial schema (same fields as the web version).
  (db) async {
    await db.execute('''
      CREATE TABLE bets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        selection TEXT NOT NULL,
        event TEXT NOT NULL DEFAULT '',
        sport TEXT NOT NULL DEFAULT 'Other',
        date TEXT NOT NULL,
        stake REAL NOT NULL,
        odds REAL NOT NULL,
        book TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        cashout REAL,
        notes TEXT NOT NULL DEFAULT '',
        created TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_bets_date ON bets(date)');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  },
  // 1 -> 2: bet types and parlay legs. Existing bets become singles.
  (db) async {
    await db.execute("ALTER TABLE bets ADD COLUMN bet_type TEXT NOT NULL DEFAULT 'single'");
    await db.execute('''
      CREATE TABLE bet_legs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bet_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        selection TEXT NOT NULL,
        event TEXT NOT NULL DEFAULT '',
        sport TEXT NOT NULL DEFAULT 'Other',
        odds REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
      )''');
    await db.execute('CREATE INDEX idx_bet_legs_bet ON bet_legs(bet_id)');
  },
];

int get schemaVersion => migrations.length;

class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static const fileName = 'bank_track.db';

  /// Opens the database in the app's private storage. Pass [factory] and
  /// [path] in tests to use an in-memory or desktop database.
  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: (db, from, to) => _migrate(db, from, to),
        // An older build opening a newer database: keep the data untouched
        // and refuse rather than let sqflite wipe or corrupt it.
        onDowngrade: (db, from, to) =>
            throw StateError('Database version $from is newer than this app ($to). Update the app.'),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    // sqflite runs onCreate/onUpgrade inside a transaction, so a failed step
    // rolls back and the previous version's data stays intact.
    for (var v = from; v < to; v++) {
      await migrations[v](db);
    }
  }

  Future<void> close() => db.close();

  // Bets
  Future<List<Bet>> bets() async {
    final legs = <int, List<BetLeg>>{};
    for (final r in await db.query('bet_legs', orderBy: 'bet_id, position')) {
      legs.putIfAbsent(r['bet_id'] as int, () => []).add(BetLeg.fromRow(r));
    }
    return (await db.query(
      'bets',
      orderBy: 'date DESC, created DESC',
    )).map((r) => Bet.fromRow(r, legs[r['id']] ?? const [])).toList();
  }

  /// Saves the bet and replaces its legs in one transaction.
  Future<int> saveBet(Bet b) => db.transaction((txn) async {
    final int id;
    if (b.id == null) {
      id = await txn.insert('bets', b.toRow());
    } else {
      id = b.id!;
      await txn.update('bets', b.toRow(), where: 'id = ?', whereArgs: [id]);
      await txn.delete('bet_legs', where: 'bet_id = ?', whereArgs: [id]);
    }
    for (var i = 0; i < b.legs.length; i++) {
      await txn.insert('bet_legs', b.legs[i].toRow(id, i));
    }
    return id;
  });

  Future<void> deleteBet(int id) => db.transaction((txn) async {
    await txn.delete('bet_legs', where: 'bet_id = ?', whereArgs: [id]);
    await txn.delete('bets', where: 'id = ?', whereArgs: [id]);
  });

  // Deposits and withdrawals
  Future<List<BankTx>> transactions() async =>
      (await db.query('transactions', orderBy: 'date DESC, id DESC')).map(BankTx.fromRow).toList();

  Future<int> saveTx(BankTx t) async {
    if (t.id == null) return db.insert('transactions', t.toRow());
    await db.update('transactions', t.toRow(), where: 'id = ?', whereArgs: [t.id]);
    return t.id!;
  }

  Future<void> deleteTx(int id) => db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  // Small app preferences (e.g. the Matches tab country), stored next to settings.
  Future<String?> pref(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['pref.$key']);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPref(String key, String value) =>
      db.insert('settings', {'key': 'pref.$key', 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  // Settings
  Future<Settings> settings() async {
    final rows = await db.query('settings');
    return Settings.fromMap({for (final r in rows) r['key'] as String: r['value'] as String});
  }

  Future<void> saveSettings(Settings s) => db.transaction((txn) async {
    for (final e in s.toMap().entries) {
      await txn.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}
