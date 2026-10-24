import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart' hide TableRow;
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../logic/stake_stats.dart';
import 'format.dart';
import 'matches_screen.dart' show TeamLogo;
import 'pro_tips_page.dart' show TipMatchLine;

Future<void> openStakeBuilder(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StakeBuilderPage(store: store, api: api, today: today),
    ));

/// The stake builder: stats picked from one or more matches, and a check of
/// each against its match.
class StakeBuilderPage extends StatefulWidget {
  const StakeBuilderPage({super.key, required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  State<StakeBuilderPage> createState() => _StakeBuilderPageState();
}

class _StakeBuilderPageState extends State<StakeBuilderPage> {
  StakeReview? _review;

  /// The stake [_review] was made for: a change to the stake drops it.
  String _reviewed = '';
  bool _checking = false;

  BankStore get store => widget.store;
  String get _signature => store.stake.map((p) => '${p.slot}|${p.over}|${p.line}').join(',');

  Future<void> _addMatch() async {
    final m = await Navigator.of(context).push<Match>(MaterialPageRoute(
      builder: (_) => StakeMatchPicker(api: widget.api, today: widget.today),
    ));
    if (m != null && mounted) await _openMatch(m);
  }

  Future<void> _openMatch(Match m) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => StakeMatchPage(match: m, store: store, api: widget.api),
      ));

  Future<void> _validate() async {
    setState(() => _checking = true);
    final picks = [...store.stake];
    final byMatch = <String, List<StakePick>>{};
    for (final p in picks) {
      (byMatch[p.matchId] ??= []).add(p);
    }
    final checks = <String, PickCheck>{};
    await Future.wait([
      for (final group in byMatch.values)
        () async {
          final m = group.first.toMatch();
          MatchDetails? result;
          StakeStats? stats;
          try {
            result = await widget.api.details(m, refresh: true);
            if (result.state != MatchState.live && result.state != MatchState.finished) {
              stats = await widget.api.stakeStats(m);
            }
          } catch (_) {
            // Checked by the hit rate saved with each pick.
          }
          for (final p in group) {
            checks[p.slot] = checkPick(p, stats: stats, result: result);
          }
        }(),
    ]);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _review = StakeReview([for (final p in picks) ?checks[p.slot]]);
      _reviewed = picks.map((p) => '${p.slot}|${p.over}|${p.line}').join(',');
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Clear this stake?')),
        content: Text(tr('Every pick in it is removed.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Clear'))),
        ],
      ),
    );
    if (ok == true) await store.clearStake();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final picks = store.stake;
          final review = _reviewed == _signature ? _review : null;
          final checks = {for (final c in review?.checks ?? const <PickCheck>[]) c.pick.slot: c};
          final byMatch = <String, List<StakePick>>{};
          for (final p in picks) {
            (byMatch[p.matchId] ??= []).add(p);
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(tr('Stake builder')),
              actions: [
                if (picks.isNotEmpty)
                  IconButton(tooltip: tr('Clear stake'), icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
              ],
            ),
            body: picks.isEmpty
                ? _Empty(onPick: _addMatch)
                : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                    if (review != null) ...[_ReviewCard(review: review), const SizedBox(height: 12)],
                    for (final group in byMatch.values) ...[
                      _MatchGroup(
                        picks: group,
                        checks: checks,
                        onRemove: store.removeStakePick,
                        onAdd: () => _openMatch(group.first.toMatch()),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      key: const Key('stake-add-match'),
                      onPressed: _addMatch,
                      icon: const Icon(Icons.add),
                      label: Text(tr('Add another match')),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr("Validate checks every pick against its match: before kick-off by how often it came in over both teams' latest games, once the match starts by the match's own stats."),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
            bottomNavigationBar: picks.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton.icon(
                        key: const Key('stake-validate'),
                        onPressed: _checking ? null : _validate,
                        icon: _checking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.fact_check_outlined),
                        label: Text(trn(picks.length, 'Validate stake ({n} pick)', 'Validate stake ({n} picks)')),
                      ),
                    ),
                  ),
          );
        },
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.query_stats, size: 56, color: cs.primary),
          const SizedBox(height: 16),
          Text(tr('Build a stake from match stats'),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            tr("Pick a match to see both teams' goals, corners, cards, shots and fouls over their latest games. Add the lines you like, add more matches, then validate the stake."),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('stake-pick-match'),
            onPressed: onPick,
            icon: const Icon(Icons.search),
            label: Text(tr('Pick a match')),
          ),
        ]),
      ),
    );
  }
}

/// A verdict's color: the app's win and loss colors, amber in between.
Color verdictColor(BuildContext context, PickVerdict v) => v.good
    ? BankColors.win(context)
    : v.bad
        ? BankColors.loss(context)
        : v == PickVerdict.noData
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Colors.amber.shade700;

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final StakeReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final counts = <PickVerdict, int>{};
    for (final c in review.checks) {
      counts[c.verdict] = (counts[c.verdict] ?? 0) + 1;
    }
    return Card(
      key: const Key('stake-review'),
      margin: EdgeInsets.zero,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.fact_check, color: cs.onPrimaryContainer),
            const SizedBox(width: 8),
            Text(tr('Stake check'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
          ]),
          const SizedBox(height: 8),
          Text(review.summary, style: TextStyle(color: cs.onPrimaryContainer)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final v in PickVerdict.values)
              if (counts[v] case final n?) _Badge(text: '${v.title} · $n', color: verdictColor(context, v)),
          ]),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
      );
}

class _MatchGroup extends StatelessWidget {
  const _MatchGroup({required this.picks, required this.checks, required this.onRemove, required this.onAdd});
  final List<StakePick> picks;
  final Map<String, PickCheck> checks;
  final void Function(StakePick) onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final first = picks.first;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            TeamLogo(url: first.homeLogo, name: first.home, size: 22),
            const SizedBox(width: 2),
            TeamLogo(url: first.awayLogo, name: first.away, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(first.matchTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('${DateFormat.MMMd().add_Hm().format(first.kickoff.toLocal())} · ${first.leagueName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            TextButton(onPressed: onAdd, child: Text(tr('Add stats'))),
          ]),
          const SizedBox(height: 4),
          for (final p in picks) _PickRow(pick: p, check: checks[p.slot], onRemove: () => onRemove(p)),
        ]),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.pick, required this.check, required this.onRemove});
  final StakePick pick;
  final PickCheck? check;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = check;
    final rate = pick.hitRate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(pick.label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (c != null) _Badge(text: c.verdict.title, color: verdictColor(context, c.verdict)),
            ]),
            Text(
              c?.note ??
                  (rate == null
                      ? tr('No recent games to rate it.')
                      : tr('Came in {rate} of the latest games.', {'rate': '${(rate * 100).round()}%'})),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        IconButton(
          tooltip: tr('Remove'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 20),
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ Match picker

/// The day's soccer matches, a few days ahead, filtered as you type.
class StakeMatchPicker extends StatefulWidget {
  const StakeMatchPicker({super.key, required this.api, this.today});
  final FixturesApi api;
  final DateTime? today;

  @override
  State<StakeMatchPicker> createState() => _StakeMatchPickerState();
}

class _StakeMatchPickerState extends State<StakeMatchPicker> {
  final _query = TextEditingController();
  var _day = 0;
  List<Match>? _all;
  String? _error;

  DateTime get _base {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _all = null;
      _error = null;
    });
    final day = _day;
    try {
      final list = await widget.api.matchesOn(_base.add(Duration(days: day)));
      if (mounted && day == _day) setState(() => _all = list);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _dayLabel(int i) => switch (i) {
        0 => tr('Today'),
        1 => tr('Tomorrow'),
        _ => DateFormat.MMMEd().format(_base.add(Duration(days: i))),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = plainText(_query.text).trim();
    final list = [
      for (final m in _all ?? const <Match>[])
        if (q.isEmpty || plainText('${m.home.name} ${m.away.name} ${m.league.name}').contains(q)) m,
    ];
    Widget message(IconData icon, String text, [Widget? action]) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              if (action != null) ...[const SizedBox(height: 16), action],
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          decoration: InputDecoration(hintText: tr('Search a team or league'), border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_dayLabel(i)),
                  selected: _day == i,
                  onSelected: (_) {
                    setState(() => _day = i);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _all == null
              ? (_error == null
                  ? const Center(child: CircularProgressIndicator())
                  : message(Icons.cloud_off, _error!, FilledButton.tonal(onPressed: _load, child: Text(tr('Try again')))))
              : list.isEmpty
                  ? message(Icons.search_off, q.isEmpty ? tr('No soccer matches on this day.') : tr('No match for "{query}".', {'query': _query.text}))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (context, i) => TipMatchLine(match: list[i], onTap: () => Navigator.pop(context, list[i])),
                    ),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- Match stats

/// One match's advanced stats: each team's latest games and, stat by stat,
/// the averages and the lines to add to the stake.
class StakeMatchPage extends StatefulWidget {
  const StakeMatchPage({super.key, required this.match, required this.store, required this.api});
  final Match match;
  final BankStore store;
  final FixturesApi api;

  @override
  State<StakeMatchPage> createState() => _StakeMatchPageState();
}

class _StakeMatchPageState extends State<StakeMatchPage> {
  StakeStats? _stats;
  String? _error;
  final _scope = <StakeStat, StakeScope>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _stats = null;
      _error = null;
    });
    try {
      final s = await widget.api.stakeStats(widget.match);
      if (mounted) setState(() => _stats = s);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr("Couldn't load this match's stats. Check your connection and try again."));
    }
  }

  Future<void> _toggle(StakeStats s, StakeStat stat, StakeScope scope, bool over, double line) async {
    final store = widget.store;
    final p = StakePick.of(widget.match, s, stat, scope, over: over, line: line);
    final now = store.stake.where((x) => x.slot == p.slot).firstOrNull;
    if (now != null && now.over == over && now.line == line) {
      await store.removeStakePick(now);
    } else {
      await store.addStakePick(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = widget.match;
    final s = _stats;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final n = widget.store.stake.length;
        return Scaffold(
          appBar: AppBar(title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          body: s == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.cloud_off, size: 40, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
                          ]),
                        ),
                )
              : s.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(tr('No recent games with stats for these teams yet.'),
                            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    )
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                      Text(
                        tr("Averages over each team's last {n} games. Tap a line to add it to your stake; the percentage is how often it came in.",
                            {'n': [s.home.games.length, s.away.games.length].reduce((a, b) => a > b ? a : b)}),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _RecentGames(form: s.home, logo: m.home.logo),
                      const SizedBox(height: 8),
                      _RecentGames(form: s.away, logo: m.away.logo),
                      const SizedBox(height: 12),
                      for (final stat in StakeStat.values)
                        if (s.expected(stat, StakeScope.match) != null) ...[
                          _StatCard(
                            stats: s,
                            stat: stat,
                            match: m,
                            scope: _scope[stat] ?? StakeScope.match,
                            onScope: (v) => setState(() => _scope[stat] = v),
                            picked: widget.store.stake.where((p) => p.matchId == m.id && p.stat == stat).toList(),
                            onLine: (scope, over, line) => _toggle(s, stat, scope, over, line),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ]),
          bottomNavigationBar: n == 0
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      key: const Key('stake-view'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.receipt_long),
                      label: Text(trn(n, 'View stake ({n} pick)', 'View stake ({n} picks)')),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// A team's latest scores, newest first, colored by result.
class _RecentGames extends StatelessWidget {
  const _RecentGames({required this.form, this.logo});
  final TeamForm form;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TeamLogo(url: logo, name: form.team, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(form.team, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final g in form.games)
              Tooltip(
                message: '${g.atHome ? tr('vs') : tr('at')} ${g.opponent}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (g.goalsFor > g.goalsAgainst
                            ? BankColors.win(context)
                            : g.goalsFor < g.goalsAgainst
                                ? BankColors.loss(context)
                                : cs.onSurfaceVariant)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(g.score, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ]),
      ),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.stats,
    required this.stat,
    required this.match,
    required this.scope,
    required this.onScope,
    required this.picked,
    required this.onLine,
  });
  final StakeStats stats;
  final StakeStat stat;
  final Match match;
  final StakeScope scope;
  final ValueChanged<StakeScope> onScope;
  final List<StakePick> picked;
  final void Function(StakeScope scope, bool over, double line) onLine;

  static String _n(double? x) => x == null ? '-' : x.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final head = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700);
    final cell = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    TableRow row(String team, TeamForm f) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(team, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(_n(f.avgFor(stat)), style: cell, textAlign: TextAlign.end),
          Text(_n(f.avgAgainst(stat)), style: cell, textAlign: TextAlign.end),
          Text(_n(f.avgTotal(stat)), style: cell, textAlign: TextAlign.end),
        ]);
    final lines = stats.lines(stat, scope);
    return Card(
      key: Key('stake-stat-${stat.name}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(stat.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text(tr('Expected {n}', {'n': _n(stats.expected(stat, StakeScope.match))}),
                style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()},
            children: [
              TableRow(children: [
                const SizedBox.shrink(),
                Text(tr('For'), style: head, textAlign: TextAlign.end),
                Text(tr('Against'), style: head, textAlign: TextAlign.end),
                Text(tr('Total'), style: head, textAlign: TextAlign.end),
              ]),
              row(match.home.name, stats.home),
              row(match.away.name, stats.away),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<StakeScope>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: StakeScope.match, label: Text(tr('Match'))),
                ButtonSegment(
                    value: StakeScope.home,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(match.home.name, maxLines: 1))),
                ButtonSegment(
                    value: StakeScope.away,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(match.away.name, maxLines: 1))),
              ],
              selected: {scope},
              onSelectionChanged: (v) => onScope(v.first),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final line in lines)
              for (final over in [true, false])
                () {
                  final rate = stats.hitRate(stat, scope, over: over, line: line);
                  final on = picked.any((p) => p.scope == scope && p.over == over && p.line == line);
                  final args = {'line': lineText(line)};
                  return FilterChip(
                    key: Key('stake-line-${stat.name}-${scope.name}-${over ? 'over' : 'under'}-${lineText(line)}'),
                    selected: on,
                    showCheckmark: false,
                    label: Text(
                        '${over ? tr('Over {line}', args) : tr('Under {line}', args)} · ${rate == null ? '-' : '${(rate * 100).round()}%'}'),
                    onSelected: (_) => onLine(scope, over, line),
                  );
                }(),
          ]),
        ]),
      ),
    );
  }
}
