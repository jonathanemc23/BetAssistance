import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'board.dart';
import 'favorites.dart';
import 'models.dart';
import 'odds_history.dart';
import 'parlay.dart';

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
  // 2 -> 3: Matchboard workspaces, their chat and their notes.
  (db) async {
    await db.execute('''
      CREATE TABLE boards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_id TEXT NOT NULL UNIQUE,
        league_slug TEXT NOT NULL,
        league_name TEXT NOT NULL DEFAULT '',
        home TEXT NOT NULL,
        away TEXT NOT NULL,
        home_logo TEXT,
        away_logo TEXT,
        kickoff TEXT NOT NULL,
        created TEXT NOT NULL,
        updated TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE board_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        board_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        created TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_board_messages_board ON board_messages(board_id)');
    await db.execute('''
      CREATE TABLE board_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        board_id INTEGER NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'assistant',
        pinned INTEGER NOT NULL DEFAULT 0,
        created TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_board_notes_board ON board_notes(board_id)');
  },
  // 3 -> 4: Parlay builder. Legs keep the match they came from, if any.
  (db) async {
    await db.execute('''
      CREATE TABLE parlays (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        stake REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        check_json TEXT,
        created TEXT NOT NULL,
        updated TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE parlay_legs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parlay_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        selection TEXT NOT NULL,
        event TEXT NOT NULL DEFAULT '',
        sport TEXT NOT NULL DEFAULT 'Other',
        odds REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        match_id TEXT,
        league_slug TEXT,
        league_name TEXT,
        home TEXT,
        away TEXT,
        kickoff TEXT
      )''');
    await db.execute('CREATE INDEX idx_parlay_legs_parlay ON parlay_legs(parlay_id)');
  },
  // 4 -> 5: a bet's market and the match it was picked from (for Review bet).
  (db) async {
    await db.execute("ALTER TABLE bets ADD COLUMN market TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE bets ADD COLUMN match_id TEXT');
    await db.execute('ALTER TABLE bets ADD COLUMN league_slug TEXT');
    await db.execute('ALTER TABLE bets ADD COLUMN league_name TEXT');
    await db.execute('ALTER TABLE bets ADD COLUMN kickoff TEXT');
  },
  // 5 -> 6: favourite matches.
  (db) async {
    await db.execute('''
      CREATE TABLE favorites (
        match_id TEXT PRIMARY KEY,
        league_slug TEXT NOT NULL,
        league_name TEXT NOT NULL DEFAULT '',
        home TEXT NOT NULL,
        away TEXT NOT NULL,
        home_logo TEXT,
        away_logo TEXT,
        kickoff TEXT NOT NULL,
        added TEXT NOT NULL
      )''');
  },
  // 6 -> 7: match prices seen over time, for the money movement tool.
  (db) async {
    await db.execute('''
      CREATE TABLE odds_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_id TEXT NOT NULL,
        at TEXT NOT NULL,
        provider TEXT NOT NULL DEFAULT '',
        home REAL,
        draw REAL,
        away REAL
      )''');
    await db.execute('CREATE INDEX odds_history_match ON odds_history(match_id, at)');
  },
  // 7 -> 8: parlay legs keep the match they were picked from, so they can
  // be settled from the final score.
  (db) async {
    await db.execute('ALTER TABLE bet_legs ADD COLUMN match_id TEXT');
    await db.execute('ALTER TABLE bet_legs ADD COLUMN league_slug TEXT');
    await db.execute('ALTER TABLE bet_legs ADD COLUMN league_name TEXT');
    await db.execute('ALTER TABLE bet_legs ADD COLUMN kickoff TEXT');
  },
  // 8 -> 9: a new bankroll starts at 0 (it was 1000). Someone already
  // tracking bets who never set a starting balance keeps the 1000 they saw.
  (db) async {
    final set = await db.query('settings', where: 'key = ?', whereArgs: ['startBankroll']);
    if (set.isNotEmpty) return;
    final used = await db.rawQuery('SELECT (SELECT COUNT(*) FROM bets) + (SELECT COUNT(*) FROM transactions) AS n');
    if (((used.first['n'] as int?) ?? 0) == 0) return;
    await db.insert('settings', {'key': 'startBankroll', 'value': '1000.0'});
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
    return (await db.query('bets', orderBy: 'date DESC, created DESC'))
        .map((r) => Bet.fromRow(r, legs[r['id']] ?? const []))
        .toList();
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

  Future<void> setPref(String key, String value) => db.insert('settings', {'key': 'pref.$key', 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

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

  // Matchboard
  Future<List<Board>> boards() async => (await db.rawQuery('''
        SELECT b.*,
          (SELECT COUNT(*) FROM board_notes n WHERE n.board_id = b.id) AS note_count,
          (SELECT n.title FROM board_notes n WHERE n.board_id = b.id ORDER BY n.id DESC LIMIT 1) AS last_note
        FROM boards b ORDER BY b.updated DESC''')).map(Board.fromRow).toList();

  /// The board for a match, created on first use.
  Future<Board> boardFor(Board draft) async {
    final rows = await db.query('boards', where: 'match_id = ?', whereArgs: [draft.matchId]);
    if (rows.isNotEmpty) return Board.fromRow(rows.first);
    final id = await db.insert('boards', draft.toRow());
    return Board.fromRow({...draft.toRow(), 'id': id});
  }

  Future<void> touchBoard(int id, String now) =>
      db.update('boards', {'updated': now}, where: 'id = ?', whereArgs: [id]);

  /// Deletes a board the user chose to remove, with its chat and notes.
  Future<void> deleteBoard(int id) => db.transaction((txn) async {
        await txn.delete('board_messages', where: 'board_id = ?', whereArgs: [id]);
        await txn.delete('board_notes', where: 'board_id = ?', whereArgs: [id]);
        await txn.delete('boards', where: 'id = ?', whereArgs: [id]);
      });

  Future<List<BoardMessage>> messages(int boardId) async =>
      (await db.query('board_messages', where: 'board_id = ?', whereArgs: [boardId], orderBy: 'id'))
          .map(BoardMessage.fromRow)
          .toList();

  Future<int> addMessage(BoardMessage m) => db.insert('board_messages', m.toRow());

  Future<List<BoardNote>> notes(int boardId) async => (await db.query('board_notes',
          where: 'board_id = ?', whereArgs: [boardId], orderBy: 'pinned DESC, id DESC'))
      .map(BoardNote.fromRow)
      .toList();

  Future<int> addNote(BoardNote n) => db.insert('board_notes', n.toRow());

  Future<void> setNotePinned(int id, bool pinned) =>
      db.update('board_notes', {'pinned': pinned ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteNote(int id) => db.delete('board_notes', where: 'id = ?', whereArgs: [id]);

  // Parlay builder
  Future<List<Parlay>> parlays() async {
    final rows = await db.query('parlays', orderBy: 'updated DESC, id DESC');
    final legs = <int, List<ParlayLeg>>{};
    for (final r in await db.query('parlay_legs', orderBy: 'parlay_id, position')) {
      legs.putIfAbsent(r['parlay_id'] as int, () => []).add(ParlayLeg.fromRow(r));
    }
    return [for (final r in rows) Parlay.fromRow(r, legs[r['id']] ?? const [])];
  }

  /// Inserts or updates a parlay and replaces its legs. Returns its id.
  Future<int> saveParlay(Parlay p) => db.transaction((txn) async {
        final row = p.toRow()..remove('id');
        final id = p.id ?? await txn.insert('parlays', row);
        if (p.id != null) await txn.update('parlays', row, where: 'id = ?', whereArgs: [id]);
        await txn.delete('parlay_legs', where: 'parlay_id = ?', whereArgs: [id]);
        for (var i = 0; i < p.legs.length; i++) {
          await txn.insert('parlay_legs', p.legs[i].toRow(id, i));
        }
        return id;
      });

  Future<void> deleteParlay(int id) => db.transaction((txn) async {
        await txn.delete('parlay_legs', where: 'parlay_id = ?', whereArgs: [id]);
        await txn.delete('parlays', where: 'id = ?', whereArgs: [id]);
      });

  Future<List<FavoriteMatch>> favorites() async =>
      [for (final r in await db.query('favorites', orderBy: 'kickoff')) FavoriteMatch.fromRow(r)];

  Future<void> saveFavorite(FavoriteMatch f) =>
      db.insert('favorites', f.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteFavorite(String matchId) => db.delete('favorites', where: 'match_id = ?', whereArgs: [matchId]);

  Future<void> deleteAllFavorites() => db.delete('favorites');

  // Account sync
  /// Tables that make up the user's own data, saved on their account.
  /// odds_history is left out: it is a cache of prices, rebuilt as matches
  /// are opened.
  static const syncedTables = [
    'bets',
    'bet_legs',
    'transactions',
    'settings',
    'boards',
    'board_messages',
    'board_notes',
    'parlays',
    'parlay_legs',
    'favorites',
  ];

  /// Preferences that belong to this device, not the account: the sign-in
  /// itself, alerts and push, the AI key and the Matches tab's filters.
  static const devicePrefs = ['account.', 'sync.', 'alerts.', 'push.', 'ai.', 'matches.'];

  static bool isDeviceSetting(String key) =>
      key.startsWith('pref.') && devicePrefs.any((p) => key.substring(5).startsWith(p));

  /// Every row of the user's data, in a fixed order so the same data always
  /// gives the same snapshot.
  Future<Map<String, Object?>> exportSnapshot() async {
    final tables = <String, Object?>{};
    for (final t in syncedTables) {
      final rows = await db.query(t, orderBy: t == 'settings' ? 'key' : t == 'favorites' ? 'match_id' : 'id');
      tables[t] = [
        for (final r in rows)
          if (t != 'settings' || !isDeviceSetting(r['key'] as String)) r,
      ];
    }
    return {'schema': schemaVersion, 'tables': tables};
  }

  /// Deletes the user's data and the price cache, keeping this device's own
  /// preferences (see [devicePrefs]) and the app's theme and language.
  Future<void> clearUserData() => db.transaction((txn) async {
        for (final t in syncedTables) {
          if (t == 'settings') continue;
          await txn.delete(t);
        }
        await txn.delete('odds_history');
        for (final r in await txn.query('settings')) {
          final key = r['key'] as String;
          // The look and language stay: they aren't private.
          if (isDeviceSetting(key) || key.startsWith('pref.app.')) continue;
          await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
        }
      });

  /// Replaces the user's data with [snapshot] in one transaction, keeping
  /// this device's own preferences. A snapshot from a newer app is refused.
  Future<void> importSnapshot(Map<String, dynamic> snapshot) async {
    final schema = snapshot['schema'] as int? ?? 0;
    if (schema > schemaVersion) {
      throw StateError('This data was saved by a newer version of the app. Update the app.');
    }
    final tables = (snapshot['tables'] as Map?) ?? const {};
    await db.transaction((txn) async {
      for (final t in syncedTables) {
        final rows = tables[t];
        if (rows is! List) continue;
        if (t == 'settings') {
          final keep = [
            for (final r in await txn.query('settings'))
              if (isDeviceSetting(r['key'] as String)) r,
          ];
          await txn.delete('settings');
          for (final r in keep) {
            await txn.insert('settings', r);
          }
        } else {
          await txn.delete(t);
        }
        for (final r in rows) {
          final row = Map<String, Object?>.from(r as Map);
          if (t == 'settings' && isDeviceSetting(row['key'] as String)) continue;
          await txn.insert(t, row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  // Odds history
  Future<List<OddsSnapshot>> oddsHistory(String matchId) async => [
        for (final r in await db.query('odds_history', where: 'match_id = ?', whereArgs: [matchId], orderBy: 'at'))
          OddsSnapshot.fromRow(r),
      ];

  Future<void> addOddsSnapshot(String matchId, OddsSnapshot s) =>
      db.insert('odds_history', {'match_id': matchId, ...s.toRow()});
}
