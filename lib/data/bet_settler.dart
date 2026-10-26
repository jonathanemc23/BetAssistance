import '../l10n/l10n.dart';
import '../logic/auto_settle.dart';
import '../logic/live_alerts.dart';
import '../logic/markets.dart';
import '../logic/nba_stake.dart';
import 'fixtures.dart';
import 'models.dart';
import 'store.dart';

/// Puts in the results of open bets once their matches are over, from the
/// same feeds the app reads: the user's bets (singles and parlay legs picked
/// from the Matches list), Parlay builder parlays, community bets and NBA
/// pro stakes. Run by [LiveAlertService] when the app starts, after each
/// full time and every few minutes in between.
class BetSettler {
  BetSettler({
    required this.store,
    required FixturesApi api,
    DateTime Function()? clock,
    Future<Map<String, Match>> Function(List<Match>)? read,
    Future<NbaBoxScore?> Function(String gameId)? box,
  })  : _clock = clock ?? DateTime.now,
        _read = read ?? ((ms) => api.refreshMatches(ms, refresh: true, urgent: false)),
        _box = box ?? api.nbaBoxScore;

  final BankStore store;
  final DateTime Function() _clock;
  final Future<Map<String, Match>> Function(List<Match>) _read;
  final Future<NbaBoxScore?> Function(String) _box;

  /// One round. Returns a notice for each of the user's bets it settled.
  Future<List<LiveAlert>> run() async {
    final now = _clock().toUtc();
    final want = <String, Match>{};
    void need(Match m) {
      if (dueForResult(m.kickoff, now)) want.putIfAbsent(m.id, () => m);
    }

    for (final b in store.bets) {
      if (b.status != BetStatus.pending) continue;
      if (b.isParlay) {
        for (final l in b.legs) {
          if (l.status == BetStatus.pending && l.isLinked) need(legMatch(l));
        }
      } else if (betMatch(b) case final m?) {
        need(m);
      }
    }
    for (final p in store.parlays) {
      if (!p.isOpen) continue;
      for (final l in p.legs) {
        if (l.status != BetStatus.pending) continue;
        if (l.toMatch() case final m?) need(withKnownLeague(m));
      }
    }
    for (final b in store.openCommunityBets) {
      need(b.toMatch());
    }
    final stakes = [for (final s in store.proStakes) if (s.status == BetStatus.pending) s];
    for (final s in stakes) {
      for (final l in s.legs) {
        if (l.status == BetStatus.pending) need(nbaMatch(l.gameId, l.home, l.away, l.tipoff));
      }
    }
    if (want.isEmpty) return const [];

    final read = await _read(want.values.toList());
    final scores = <String, Match>{
      for (final m in read.values)
        if (finalScore(m) != null) m.id: m,
    };
    if (scores.isEmpty) return const [];

    // Box scores, read once per finished NBA game that has a player line on it.
    final boxes = <String, NbaBoxScore>{};
    Future<NbaBoxScore?> boxFor(String id) async {
      if (boxes[id] case final b?) return b;
      final b = await _box(id);
      if (b != null && b.finished) boxes[id] = b;
      return b;
    }

    Future<BetStatus?> grade(String selection, String market, Match? m) async {
      if (m == null) return null;
      final prop = parsePropPick(selection);
      if (prop != null) {
        if (m.league.knownSport != Sport.basketball) return null;
        final box = await boxFor(m.id);
        return box == null ? null : gradeProp(prop.$1, prop.$2, prop.$3, box);
      }
      return gradeOnScore(market, selection, m);
    }

    // The user's bets.
    final settled = <Bet>[];
    final alerts = <LiveAlert>[];
    for (final b in store.bets) {
      if (b.status != BetStatus.pending) continue;
      Bet? next;
      if (b.isParlay) {
        var changed = false;
        final legs = <BetLeg>[];
        for (final l in b.legs) {
          final r = l.status == BetStatus.pending && l.isLinked
              ? await grade(l.selection, marketOf(l.selection), scores[l.matchId])
              : null;
          if (r != null) changed = true;
          legs.add(r == null ? l : l.copyWith(status: r));
        }
        if (changed) next = b.copyWith(legs: legs, status: parlayStatus(legs));
      } else if (b.matchId != null) {
        final r = await grade(b.selection, b.market.isNotEmpty ? b.market : marketOf(b.selection), scores[b.matchId]);
        if (r != null) next = b.copyWith(status: r);
      }
      if (next == null) continue;
      settled.add(next);
      if (next.status != BetStatus.pending) alerts.add(settledAlert(next, scores[b.matchId]));
    }
    await store.saveSettled(settled);

    // Parlay builder parlays.
    for (final p in [...store.parlays]) {
      if (!p.isOpen) continue;
      var current = p;
      for (final (i, l) in p.legs.indexed) {
        if (l.status != BetStatus.pending || !l.isLinked) continue;
        final r = await grade(l.selection, marketOf(l.selection), scores[l.matchId]);
        if (r != null) current = await store.setLegStatus(current, i, r);
      }
    }

    // Community bets, settled from the final score like the challenge page does.
    final community = {for (final b in store.openCommunityBets) b.matchId};
    for (final id in community) {
      final m = scores[id];
      if (m == null) continue;
      final (h, a) = finalScore(m)!;
      await store.settleCommunity(id, h, a);
    }

    // Pro stakes.
    final changed = <ProStake>[];
    for (final s in stakes) {
      var any = false;
      final legs = <NbaProp>[];
      for (final l in s.legs) {
        BetStatus? r;
        if (l.status == BetStatus.pending && scores.containsKey(l.gameId)) {
          final box = await boxFor(l.gameId);
          if (box != null) r = l.grade(box);
        }
        if (r != null) any = true;
        legs.add(r == null ? l : l.withStatus(r));
      }
      if (any) changed.add(s.withLegs(legs));
    }
    await store.updateProStakes(changed);
    return alerts;
  }
}

/// The notice for a bet [b] just settled: won, lost, or settled (push, void).
LiveAlert settledAlert(Bet b, Match? m) {
  final pick = b.isParlay ? tr('{n}-leg parlay', {'n': b.legs.length}) : trPick(b.selection);
  final title = switch (b.status) {
    BetStatus.won => tr('Bet won: {pick}', {'pick': pick}),
    BetStatus.lost => tr('Bet lost: {pick}', {'pick': pick}),
    _ => tr('Bet settled: {pick}', {'pick': pick}),
  };
  final score = m == null ? b.event : '${m.home.name} ${m.home.score}-${m.away.score} ${m.away.name}';
  final body = [score, tr('Result put in your bets automatically.')].where((s) => s.isNotEmpty).join('\n');
  return LiveAlert(AlertKind.settled, 'settle:${b.id ?? b.created}', title, body);
}
