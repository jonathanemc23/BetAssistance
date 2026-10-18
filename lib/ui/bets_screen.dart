import 'package:flutter/material.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'bet_form.dart';
import 'bet_review_page.dart';
import 'format.dart';
import 'share_ui.dart';

enum BetFilter { all, open, won, lost, parlays }

/// The bet register: every bet, filters, quick settling and sharing.
class BetsScreen extends StatefulWidget {
  const BetsScreen({super.key, required this.store, required this.api});
  final BankStore store;
  final FixturesApi api;
  @override
  State<BetsScreen> createState() => BetsScreenState();
}

class BetsScreenState extends State<BetsScreen> {
  BetFilter _filter = BetFilter.all;
  BankStore get store => widget.store;

  bool _matches(Bet b) => switch (_filter) {
    BetFilter.all => true,
    BetFilter.open => b.status == BetStatus.pending,
    BetFilter.won => b.status == BetStatus.won,
    BetFilter.lost => b.status == BetStatus.lost,
    BetFilter.parlays => b.isParlay,
  };

  Future<void> _actions(Bet b) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share link'),
              onTap: () => Navigator.pop(c, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('Log this bet again'),
              onTap: () => Navigator.pop(c, 'again'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await openBetForm(context, store, bet: b);
      case 'share':
        await showShareBet(context, store, b);
      case 'again':
        await openBetForm(
          context,
          store,
          template: b.asNew(date: isoDate(DateTime.now()), created: DateTime.now().toIso8601String()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(store.settings);
    final list = store.bets.where(_matches).toList();
    final pl = list.where((b) => b.isSettled).fold<double>(0, (a, b) => a + b.profit);
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.list(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in BetFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(switch (f) {
                            BetFilter.all => 'All',
                            BetFilter.open => 'Open',
                            BetFilter.won => 'Won',
                            BetFilter.lost => 'Lost',
                            BetFilter.parlays => 'Parlays',
                          }),
                          selected: _filter == f,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('${list.length} bets', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  Text('Settled P/L ', style: theme.textTheme.bodySmall),
                  Text(
                    fmt.money(pl, sign: true),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: BankColors.forValue(context, pl),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (store.bets.isEmpty)
                _EmptyState(onAdd: () => openBetForm(context, store))
              else if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No bets match this filter.')),
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _BetTile(
              bet: list[i],
              fmt: fmt,
              onTap: () => openBetForm(context, store, bet: list[i]),
              onLongPress: () => _actions(list[i]),
              onSettle: (st) => store.settle(list[i], st),
              onReview: () => openBetReview(context, store: store, api: widget.api, bet: list[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _BetTile extends StatelessWidget {
  const _BetTile({
    required this.bet,
    required this.fmt,
    required this.onTap,
    required this.onLongPress,
    required this.onSettle,
    required this.onReview,
  });
  final Bet bet;
  final VoidCallback onReview;
  final Fmt fmt;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(BetStatus) onSettle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = BankColors.forStatus(context, bet.status);
    final pending = bet.status == BetStatus.pending;
    final sub = betSubtitle(bet);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (bet.type != BetType.single) ...[_TypeBadge(type: bet.type), const SizedBox(width: 6)],
                          Expanded(child: Text(betTitle(bet), style: theme.textTheme.titleSmall)),
                        ],
                      ),
                      if (sub.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '${betMeta(bet, fmt)} · ${fmt.money(bet.stake)} @ ${formatOdds(bet.odds, fmt.settings.oddsFormat)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      _ReviewButton(onTap: onReview),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: color),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        bet.status.label.toUpperCase(),
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (pending)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SettleButton(
                            label: 'Won',
                            color: BankColors.win(context),
                            onTap: () => onSettle(BetStatus.won),
                          ),
                          const SizedBox(width: 6),
                          _SettleButton(
                            label: 'Lost',
                            color: BankColors.loss(context),
                            onTap: () => onSettle(BetStatus.lost),
                          ),
                        ],
                      )
                    else
                      Text(
                        fmt.money(bet.profit, sign: true),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: BankColors.forValue(context, bet.profit),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final BetType type;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(4)),
      child: Text(
        type.label.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: cs.onSecondaryContainer),
      ),
    );
  }
}

class _SettleButton extends StatelessWidget {
  const _SettleButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 32),
    ),
    child: Text(label),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your betting ledger starts here', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Log each bet with its stake and odds, as a single, a parlay or another type. '
            'Long-press a bet to share it as a link or log it again.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Log your first bet')),
        ],
      ),
    ),
  );
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fact_check_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 5),
              Text(
                'Review bet',
                style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
