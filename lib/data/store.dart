import 'package:flutter/foundation.dart';

import '../logic/stats.dart';
import 'board.dart';
import 'database.dart';
import 'favorites.dart';
import 'fixtures.dart';
import 'models.dart';
import 'odds_history.dart';
import 'parlay.dart';

/// In-memory view of the database that the screens listen to. Every change
/// is written to SQLite first, then the lists are reloaded from it.
class BankStore extends ChangeNotifier {
  BankStore(this._db);
  final AppDatabase _db;

  List<Bet> bets = [];
  List<BankTx> txs = [];
  Settings settings = Settings.defaults();
  List<Board> boards = [];
  List<Parlay> parlays = [];
  List<FavoriteMatch> favorites = [];

  /// Selected look, one of [appThemes] ids. Saved as a preference.
  String themeId = 'olive';
  bool loaded = false;

  Stats get stats => Stats.compute(settings, bets, txs);

  Future<void> load() async {
    settings = await _db.settings();
    bets = await _db.bets();
    txs = await _db.transactions();
    boards = await _db.boards();
    parlays = await _db.parlays();
    favorites = await _db.favorites();
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

  // Parlay builder
  Parlay? parlayById(int? id) => parlays.where((p) => p.id == id).firstOrNull;

  /// The open parlay worked on most recently, where new picks go by default.
  Parlay? get currentParlay => parlays.where((p) => p.isOpen).firstOrNull;

  Future<Parlay> newParlay({List<ParlayLeg> legs = const []}) async {
    var n = parlays.length + 1;
    while (parlays.any((p) => p.name == 'Parlay $n')) {
      n++;
    }
    final now = _now();
    return saveParlay(Parlay(name: 'Parlay $n', legs: legs, created: now, updated: now));
  }

  Future<Parlay> saveParlay(Parlay p) async {
    final id = await _db.saveParlay(p.copyWith(updated: _now()));
    parlays = await _db.parlays();
    notifyListeners();
    return parlayById(id)!;
  }

  Future<Parlay> addLeg(Parlay p, ParlayLeg leg) => saveParlay(p.copyWith(legs: [...p.legs, leg]));

  Future<Parlay> removeLeg(Parlay p, int index) =>
      saveParlay(p.copyWith(legs: [...p.legs]..removeAt(index), status: BetStatus.pending));

  /// Sets one leg's result; the parlay's result follows from its legs.
  Future<Parlay> setLegStatus(Parlay p, int index, BetStatus status) {
    final legs = [...p.legs]..[index] = p.legs[index].copyWith(status: status);
    return saveParlay(p.copyWith(legs: legs, status: parlayStatus([for (final l in legs) l.asBetLeg()])));
  }

  /// Sets the whole parlay's result. Won marks open legs won as well.
  Future<Parlay> setParlayStatus(Parlay p, BetStatus status) => saveParlay(p.copyWith(
        status: status,
        legs: status == BetStatus.won
            ? [for (final l in p.legs) l.status == BetStatus.pending ? l.copyWith(status: BetStatus.won) : l]
            : null,
      ));

  Future<void> deleteParlay(Parlay p) async {
    if (p.id != null) await _db.deleteParlay(p.id!);
    parlays = await _db.parlays();
    notifyListeners();
  }

  // Favourite matches
  bool isFavorite(String matchId) => favorites.any((f) => f.matchId == matchId);

  /// Stars or unstars [m]. Returns whether it is a favourite now.
  Future<bool> toggleFavorite(Match m) async {
    final starred = !isFavorite(m.id);
    if (starred) {
      await _db.saveFavorite(FavoriteMatch.fromMatch(m, _now()));
    } else {
      await _db.deleteFavorite(m.id);
    }
    favorites = await _db.favorites();
    notifyListeners();
    return starred;
  }

  /// Saves [odds] for [matchId] when the prices changed since the last
  /// reading, and returns every reading, oldest first.
  Future<List<OddsSnapshot>> recordOdds(String matchId, MatchOdds? odds, {DateTime? at}) async {
    var history = await _db.oddsHistory(matchId);
    if (odds != null) {
      final now = OddsSnapshot.of(odds, at ?? DateTime.now());
      final last = history.where((h) => h.provider == now.provider).lastOrNull;
      if (last == null || !last.samePrices(now)) {
        await _db.addOddsSnapshot(matchId, now);
        history = await _db.oddsHistory(matchId);
      }
    }
    return history.where((h) => odds == null || h.provider == odds.provider).toList();
  }

  Future<void> removeFavorite(String matchId) async {
    await _db.deleteFavorite(matchId);
    favorites = await _db.favorites();
    notifyListeners();
  }
}
