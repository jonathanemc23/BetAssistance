import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../logic/nba_stake.dart';
import 'bet_form.dart';
import 'format.dart';
import 'pro_tips_page.dart' show TokenCoin, showTokensSheet;

/// The Stake builder's locked Generate pro stake button and the pro stakes
/// bought so far. The button reads the day's NBA games first, so with none
/// left to start it says so instead of taking tokens.
class ProStakeSection extends StatefulWidget {
  const ProStakeSection({super.key, required this.store, required this.api, this.today, this.random});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  /// Tests pass a seeded one.
  final math.Random? random;

  @override
  State<ProStakeSection> createState() => _ProStakeSectionState();
}

class _ProStakeSectionState extends State<ProStakeSection> {
  List<NbaGame>? _games;
  String? _error;
  bool _busy = false;

  BankStore get store => widget.store;
  DateTime get _now => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final games = await widget.api.nbaGames(_now);
      if (mounted) setState(() => _games = games);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _generate(List<NbaGame> open) async {
    if (store.tokens < proStakeCost) {
      await showTokensSheet(context, store, need: proStakeCost);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const TokenCoin(size: 36),
        title: Text(tr('Generate an NBA pro tip?')),
        content: Text(tr(
            'It costs {n} tokens of your {tokens}. You get 2 or 3 NBA player lines from today\'s games, with total odds from 2.40 to 3.70.',
            {'n': proStakeCost, 'tokens': store.tokens})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Generate'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final stake = generateProStake(open, _now.toUtc(), widget.random ?? math.Random());
    final bought = stake != null && await store.buyProStake(stake);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(bought ? tr('Your NBA pro tip is ready.') : tr('No NBA matches today, try again tomorrow')),
    ));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final games = _games;
          final open = games == null ? const <NbaGame>[] : openGames(games, _now.toUtc());
          final recent = [
            for (final s in store.proStakes)
              if (_now.difference(s.created).inDays < 3 || s.status == BetStatus.pending) s,
          ];
          final Widget button;
          if (_error != null) {
            button = OutlinedButton.icon(
                onPressed: _load, icon: const Icon(Icons.refresh), label: Text(tr("Couldn't load the NBA games. Try again")));
          } else if (games == null) {
            button = FilledButton.icon(
              onPressed: null,
              icon: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              label: Text(tr("Checking today's NBA games…")),
            );
          } else if (open.isEmpty) {
            button = FilledButton.icon(
              key: const Key('pro-stake-none'),
              onPressed: null,
              icon: const Icon(Icons.event_busy),
              label: Text(tr('No NBA matches today, try again tomorrow'), textAlign: TextAlign.center),
            );
          } else {
            button = FilledButton.icon(
              key: const Key('pro-stake-generate'),
              onPressed: _busy ? null : () => _generate(open),
              icon: const Icon(Icons.lock),
              label: Text(tr('Generate pro tip · {n} tokens', {'n': proStakeCost})),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              margin: EdgeInsets.zero,
              color: cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.sports_basketball, color: cs.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('NBA pro tip'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800, color: cs.onSecondaryContainer)),
                    ),
                    const Icon(Icons.lock_outline, size: 18),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    games == null || open.isEmpty
                        ? tr('2 or 3 player lines from the day\'s NBA games, total odds 2.40 to 3.70.')
                        : trn(open.length, '2 or 3 player lines from {n} NBA game still to play today, total odds 2.40 to 3.70.',
                            '2 or 3 player lines from {n} NBA games still to play today, total odds 2.40 to 3.70.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSecondaryContainer),
                  ),
                  const SizedBox(height: 12),
                  button,
                ]),
              ),
            ),
            for (final s in recent) ...[const SizedBox(height: 12), ProStakeTicket(stake: s, store: store, api: widget.api)],
          ]);
        },
      );
}

/// A pro stake as a bet slip: the lines, how many are over, the total odds,
/// and Log bet.
class ProStakeTicket extends StatelessWidget {
  const ProStakeTicket({super.key, required this.stake, required this.store, required this.api});
  final ProStake stake;
  final BankStore store;
  final FixturesApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = stake;
    final status = s.status;
    final accent = switch (status) {
      BetStatus.won => BankColors.win(context),
      BetStatus.lost => BankColors.loss(context),
      _ => Colors.amber.shade700,
    };
    Color legColor(BetStatus st) => switch (st) {
          BetStatus.won => BankColors.win(context),
          BetStatus.lost => BankColors.loss(context),
          _ => cs.onSurfaceVariant,
        };
    return Card(
      key: Key('pro-stake-${s.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 5))),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: '${s.kind} • ', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(
              text: status == BetStatus.pending
                  ? tr('{done} of {n} finished', {'done': s.finished, 'n': s.legs.length})
                  : status.label,
              style: TextStyle(fontWeight: FontWeight.w800, color: accent),
            ),
          ])),
          Text(
            '${DateFormat.yMMMd().add_Hm().format(s.created.toLocal())} · ${tr('NBA pro tip')}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final l in s.legs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${l.label} - ${tr('Yes')}', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      '${l.matchTitle} · ${DateFormat.Hm().format(l.tipoff.toLocal())}',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(l.odds.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (l.status != BetStatus.pending)
                    Text(l.status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: legColor(l.status))),
                ]),
              ]),
            ),
          const Divider(height: 18),
          Row(children: [
            Text('${tr('Odds')}: ', style: TextStyle(color: cs.onSurfaceVariant)),
            Text(s.odds.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w900)),
            const Spacer(),
            if (status == BetStatus.pending)
              TextButton.icon(
                key: Key('pro-stake-log-${s.id}'),
                onPressed: () => openBetForm(context, store, template: s.toBet(stake: store.settings.unit), api: api),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Log bet')),
              ),
          ]),
        ]),
      ),
    );
  }
}
