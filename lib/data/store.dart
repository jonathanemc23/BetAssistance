import 'package:flutter/foundation.dart';

import '../logic/stats.dart';
import 'board.dart';
import 'database.dart';
import 'fixtures.dart';
import 'models.dart';

/// In-memory view of the database that the screens listen to. Every change
/// is written to SQLite first, then the lists are reloaded from it.
class BankStore extends ChangeNotifier {
  BankStore(this._db);
  final AppDatabase _db;

  List<Bet> bets = [];
  List<BankTx> txs = [];
  Settings settings = Settings.defaults();
  List<Board> boards = [];

  /// Selected look, one of [appThemes] ids. Saved as a preference.
  String themeId = 'olive';
  bool loaded = false;

  Stats get stats => Stats.compute(settings, bets, txs);

  Future<void> load() async {
    settings = await _db.settings();
    bets = await _db.bets();
    txs = await _db.transactions();
    boards = await _db.boards();
    themeId = await _db.pref('app.theme') ?? 'olive';
    loaded = true;
    notifyListeners();
  }

  Future<void> saveBet(Bet b) async {
    await _db.saveBet(b);
    await load();
  }

  Future<void> deleteBet(Bet b) async {
    if (b.id != null) await _db.deleteBet(b.id!);
    await load();
  }

  Future<void> settle(Bet b, BetStatus status) => saveBet(b.copyWith(status: status));

  Future<void> saveTx(BankTx t) async {
    await _db.saveTx(t);
    await load();
  }

  Future<void> deleteTx(BankTx t) async {
    if (t.id != null) await _db.deleteTx(t.id!);
    await load();
  }

  Future<String?> pref(String key) => _db.pref(key);
  Future<void> setPref(String key, String value) => _db.setPref(key, value);

  Future<void> saveSettings(Settings s) async {
    await _db.saveSettings(s);
    await load();
  }

  Future<void> setTheme(String id) async {
    themeId = id;
    notifyListeners();
    await _db.setPref('app.theme', id);
  }

  // Matchboard
  static String _now() => DateTime.now().toIso8601String();

  Future<Board> openBoard(Match m) async {
    final b = await _db.boardFor(Board.fromMatch(m, _now()));
    boards = await _db.boards();
    notifyListeners();
    return b;
  }

  Future<void> deleteBoard(Board b) async {
    if (b.id != null) await _db.deleteBoard(b.id!);
    boards = await _db.boards();
    notifyListeners();
  }

  Future<List<BoardMessage>> messages(Board b) => _db.messages(b.id!);
  Future<List<BoardNote>> notes(Board b) => _db.notes(b.id!);

  Future<void> addMessage(Board b, ChatRole role, String text) async {
    await _db.addMessage(BoardMessage(boardId: b.id!, role: role, text: text, created: _now()));
    await _boardChanged(b);
  }

  Future<void> addNote(Board b, {required String category, required String title, required String body, String source = 'assistant'}) async {
    await _db.addNote(BoardNote(boardId: b.id!, category: category, title: title, body: body, source: source, created: _now()));
    await _boardChanged(b);
  }

  Future<void> setNotePinned(BoardNote n, bool pinned) => _db.setNotePinned(n.id!, pinned);

  Future<void> deleteNote(Board b, BoardNote n) async {
    await _db.deleteNote(n.id!);
    await _boardChanged(b);
  }

  Future<void> _boardChanged(Board b) async {
    await _db.touchBoard(b.id!, _now());
    boards = await _db.boards();
    notifyListeners();
  }
}
