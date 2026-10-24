import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';
import '../logic/community.dart';
import '../logic/pro_tips.dart';
import '../logic/stake_stats.dart';
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

  /// Tokens to unlock Pro tips, and the tips unlocked so far by id.
  int tokens = 0;
  Map<String, UnlockedTip> unlockedTips = {};

  /// The profile picture: '' for the default, `emoji:<emoji>:<colour>` for
  /// a preset or `photo:<base64 jpeg>`. Saved as a preference with the name.
  String avatar = '';
  String profileName = '';

  /// Selected look, one of [appThemes] ids. Saved as a preference.
  String themeId = 'olive';

  /// The app's language: the saved choice, else the phone's when the app
  /// speaks it, else English.
  AppLanguage language = AppLanguage.en;
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
    final lang = await _db.pref('app.language');
    language = lang == null ? AppLanguage.device : AppLanguage.byCode(lang);
    L10n.use(language);
    avatar = await _db.pref('profile.avatar') ?? '';
    profileName = await _db.pref('profile.name') ?? '';
    await _loadTips();
    await _loadStake();
    await _loadCommunity();
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

  /// Switches the app to [l] straight away and saves the choice.
  Future<void> setLanguage(AppLanguage l) async {
    language = l;
    L10n.use(l);
    notifyListeners();
    L10n.rebuildAll();
    await _db.setPref('app.language', l.name);
  }

  Future<void> setAvatar(String value) async {
    avatar = value;
    notifyListeners();
    await _db.setPref('profile.avatar', value);
  }

  Future<void> setProfileName(String name) async {
    profileName = name.trim();
    notifyListeners();
    await _db.setPref('profile.name', profileName);
  }

  // Pro tips
  /// Tokens every new user starts with, until tokens can be bought.
  static const starterTokens = 10;

  Future<void> _loadTips() async {
    final saved = await _db.pref('tips.tokens');
    if (saved == null) {
      tokens = starterTokens;
      await _db.setPref('tips.tokens', '$tokens');
    } else {
      tokens = int.tryParse(saved) ?? 0;
    }
    final raw = await _db.pref('tips.unlocked');
    try {
      final json = raw == null ? const {} : jsonDecode(raw) as Map<String, dynamic>;
      unlockedTips = {
        for (final e in json.entries) e.key: UnlockedTip.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      unlockedTips = {};
    }
  }

  Future<void> _saveTips() async {
    await _db.setPref('tips.tokens', '$tokens');
    await _db.setPref('tips.unlocked', jsonEncode({for (final e in unlockedTips.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  bool isUnlocked(Tip t) => t.free || unlockedTips.containsKey(t.id);

  /// Spends the tip's tokens to unlock it. False when there aren't enough.
  Future<bool> unlockTip(Tip t) async {
    if (isUnlocked(t)) return true;
    if (tokens < t.cost) return false;
    tokens -= t.cost;
    unlockedTips[t.id] = UnlockedTip(cost: t.cost, at: _now(), tip: t);
    await _saveTips();
    return true;
  }

  /// Settles the unlocked tips once the final score is in: a tip that lost
  /// gives its tokens back, once.
  Future<void> settleTips(List<Tip> tips, int home, int away) async {
    var changed = false;
    for (final t in tips) {
      final u = unlockedTips[t.id];
      if (u == null || u.result != null) continue;
      final won = t.result(home, away)!;
      unlockedTips[t.id] = u.settled(won ? 'won' : 'refunded');
      if (!won) tokens += u.cost;
      changed = true;
    }
    if (changed) await _saveTips();
  }

  /// The Pro tips bought for [matchId], as they were bought.
  List<Tip> boughtTips(String matchId) => [
        for (final u in unlockedTips.values)
          if (u.tip case final t? when t.matchId == matchId) t,
      ];

  Future<void> addTokens(int n) async {
    tokens += n;
    await _saveTips();
  }

  // Stake builder
  /// The stats picked in the stake builder, in the order they were added.
  List<StakePick> stake = [];

  Future<void> _loadStake() async {
    try {
      final raw = await _db.pref('stake.picks');
      stake = [for (final j in (raw == null ? const [] : jsonDecode(raw) as List)) ?StakePick.fromJson(j)];
    } catch (_) {
      stake = [];
    }
  }

  Future<void> _saveStake() async {
    notifyListeners();
    await _db.setPref('stake.picks', jsonEncode([for (final p in stake) p.toJson()]));
  }

  /// Adds [p] to the stake, in place of a pick on the same match, stat and side.
  Future<void> addStakePick(StakePick p) async {
    final i = stake.indexWhere((x) => x.slot == p.slot);
    if (i >= 0) {
      stake[i] = p;
    } else {
      stake.add(p);
    }
    await _saveStake();
  }

  Future<void> removeStakePick(StakePick p) async {
    stake.removeWhere((x) => x.slot == p.slot);
    await _saveStake();
  }

  Future<void> clearStake() async {
    stake = [];
    await _saveStake();
  }

  // Community
  /// The user's social profile; null until they make one to enter.
  SocialProfile? socialProfile;
  ProChallenge challenge = const ProChallenge();

  /// Bets bought from the community, by listing id.
  Map<String, Listing> boughtListings = {};

  /// The user's own bets for sale, once they passed the challenge.
  List<Listing> myListings = [];

  Future<void> _loadCommunity() async {
    Object? read(String? raw) {
      try {
        return raw == null ? null : jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }

    socialProfile = SocialProfile.fromJson(read(await _db.pref('community.profile')));
    challenge = ProChallenge.fromJson(read(await _db.pref('community.challenge')));
    final bought = read(await _db.pref('community.bought'));
    boughtListings = {
      if (bought is Map)
        for (final e in bought.entries) '${e.key}': ?Listing.fromJson(e.value),
    };
    final mine = read(await _db.pref('community.selling'));
    myListings = [if (mine is List) for (final j in mine) ?Listing.fromJson(j)];
  }

  Future<void> saveSocialProfile(SocialProfile p) async {
    socialProfile = p;
    notifyListeners();
    await _db.setPref('community.profile', jsonEncode(p.toJson()));
  }

  Future<void> _saveChallenge(ProChallenge c) async {
    challenge = c;
    notifyListeners();
    await _db.setPref('community.challenge', jsonEncode(c.toJson()));
  }

  Future<void> acceptChallenge() => _saveChallenge(challenge.accept(communityClock()));

  Future<void> restartChallenge() => _saveChallenge(challenge.restart(communityClock()));

  /// Places [bet] in the challenge. The reason it can't be, or null once placed.
  Future<String?> placeChallengeBet(CommunityBet bet) async {
    final why = challenge.refuse(bet, communityClock());
    if (why != null) return why;
    await _saveChallenge(challenge.place(bet));
    return null;
  }

  /// Settles the challenge bets on [matchId] with its final score.
  Future<void> settleChallenge(String matchId, int home, int away) =>
      _saveChallenge(challenge.settle(matchId, home, away, communityClock()));

  /// Spends the listing's tokens to see its bet. False when there aren't enough.
  Future<bool> buyListing(Listing l) async {
    if (boughtListings.containsKey(l.id)) return true;
    if (tokens < l.price) return false;
    tokens -= l.price;
    boughtListings[l.id] = l;
    notifyListeners();
    await _db.setPref('community.bought', jsonEncode({for (final e in boughtListings.entries) e.key: e.value.toJson()}));
    await _saveTips();
    return true;
  }

  Future<void> sellBet(Listing l) async {
    myListings = [...myListings, l];
    notifyListeners();
    await _db.setPref('community.selling', jsonEncode([for (final x in myListings) x.toJson()]));
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

  /// Unstars every match.
  Future<void> clearFavorites() async {
    await _db.deleteAllFavorites();
    favorites = await _db.favorites();
    notifyListeners();
  }
}
