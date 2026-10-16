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
  Future<List<Bet>> bets() async =>
      (await db.query('bets', orderBy: 'date DESC, created DESC')).map(Bet.fromRow).toList();

  Future<int> saveBet(Bet b) async {
    if (b.id == null) return db.insert('bets', b.toRow());
    await db.update('bets', b.toRow(), where: 'id = ?', whereArgs: [b.id]);
    return b.id!;
  }

  Future<void> deleteBet(int id) => db.delete('bets', where: 'id = ?', whereArgs: [id]);

  // Deposits and withdrawals
  Future<List<BankTx>> transactions() async =>
      (await db.query('transactions', orderBy: 'date DESC, id DESC')).map(BankTx.fromRow).toList();

  Future<int> saveTx(BankTx t) async {
    if (t.id == null) return db.insert('transactions', t.toRow());
    await db.update('transactions', t.toRow(), where: 'id = ?', whereArgs: [t.id]);
    return t.id!;
  }

  Future<void> deleteTx(int id) => db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  // Settings
  Future<Settings> settings() async {
    final rows = await db.query('settings');
    return Settings.fromMap({for (final r in rows) r['key'] as String: r['value'] as String});
  }

  Future<void> saveSettings(Settings s) => db.transaction((txn) async {
        for (final e in s.toMap().entries) {
          await txn.insert('settings', {'key': e.key, 'value': e.value},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
}
