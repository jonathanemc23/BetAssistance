import 'package:flutter/foundation.dart';

import '../logic/stats.dart';
import 'database.dart';
import 'models.dart';

/// In-memory view of the database that the screens listen to. Every change
/// is written to SQLite first, then the lists are reloaded from it.
class BankStore extends ChangeNotifier {
  BankStore(this._db);
  final AppDatabase _db;

  List<Bet> bets = [];
  List<BankTx> txs = [];
  Settings settings = Settings.defaults();
  bool loaded = false;

  Stats get stats => Stats.compute(settings, bets, txs);

  Future<void> load() async {
    settings = await _db.settings();
    bets = await _db.bets();
    txs = await _db.transactions();
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
}
