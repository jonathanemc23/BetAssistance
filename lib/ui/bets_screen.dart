import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'bank_screens.dart';
import 'bet_form.dart';
import 'format.dart';

enum BetFilter { all, open, won, lost, settled }

/// Screen 1: bankroll control, key stats and the bet register.
class BetsScreen extends StatefulWidget {
  const BetsScreen({super.key, required this.store});
  final BankStore store;
  @override
  State<BetsScreen> createState() => BetsScreenState();
}

class BetsScreenState extends State<BetsScreen> {
  BetFilter _filter = BetFilter.all;
  BankStore get store => widget.store;

  void _toast(String? msg) {
    if (msg != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> openBet([Bet? b]) async {
    final msg = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => BetFormPage(store: store, bet: b)));
    _toast(msg);
  }

  bool _matches(Bet b) => switch (_filter) {
        BetFilter.all => true,
        BetFilter.open => b.status == BetStatus.pending,
        BetFilter.won => b.status == BetStatus.won,
        BetFilter.lost => b.status == BetStatus.lost,
        BetFilter.settled => b.isSettled,
      };

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(store.settings);
    final s = store.stats;
    final list = store.bets.where(_matches).toList();
    final theme = Theme.of(context);

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.list(children: [
          _BankCard(store: store, fmt: fmt, stats: s, onToast: _toast),
          const SizedBox(height: 12),
          _KpiGrid(tiles: [
            _Kpi('Profit / loss', fmt.money(s.profit, sign: true),
                '${s.units >= 0 ? '+' : '−'}${s.units.abs().toStringAsFixed(1)} units', BankColors.forValue(context, s.profit)),
            _Kpi('ROI', fmt.pct(s.roi), 'on ${fmt.money(s.turnover)} staked', BankColors.forValue(context, s.roi)),
            _Kpi('Win rate', '${(s.winRate * 100).toStringAsFixed(0)}%', '${s.wins}W · ${s.losses}L', null),
            _Kpi('Bets', '${s.count}', '${s.settledCount} settled · ${s.pendingCount} open', null),
            _Kpi('Avg odds', s.avgOdds == 0 ? '–' : formatOdds(s.avgOdds, store.settings.oddsFormat), 'won and lost bets', null),
            _Kpi('At risk', fmt.money(s.exposure), '${s.pendingCount} open bets', null),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Text('Bet register', style: theme.textTheme.titleLarge),
            const Spacer(),
            Text('${list.length} bets', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in BetFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(switch (f) {
                      BetFilter.all => 'All',
                      BetFilter.open => 'Open',
                      BetFilter.won => 'Won',
                      BetFilter.lost => 'Lost',
                      BetFilter.settled => 'Settled',
                    }),
                    selected: _filter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          if (store.bets.isEmpty)
            _EmptyState(onAdd: () => openBet())
          else if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No bets match this filter.'))),
        ]),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        sliver: SliverList.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _BetTile(
            bet: list[i],
            fmt: fmt,
            onTap: () => openBet(list[i]),
            onSettle: (st) => store.settle(list[i], st),
          ),
        ),
      ),
    ]);
  }
}

class _BankCard extends StatelessWidget {
  const _BankCard({required this.store, required this.fmt, required this.stats, required this.onToast});
  final BankStore store;
  final Fmt fmt;
  final Stats stats;
  final void Function(String?) onToast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BANKROLL', style: TextStyle(letterSpacing: 1.2, fontSize: 12, color: cs.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text(fmt.money(stats.balance),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: cs.onPrimaryContainer, fontFeatures: const [FontFeature.tabularFigures()])),
          Text('${fmt.money(stats.available)} available · started at ${fmt.money(store.settings.startBankroll)}',
              style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async => onToast(await showTxSheet(context, store, TxKind.deposit)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Deposit'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async => onToast(await showTxSheet(context, store, TxKind.withdrawal)),
              icon: const Icon(Icons.remove, size: 18),
              label: const Text('Withdraw'),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionsPage(store: store))),
              child: const Text('History'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Kpi {
  const _Kpi(this.label, this.value, this.sub, this.color);
  final String label, value, sub;
  final Color? color;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles});
  final List<_Kpi> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 560 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in tiles)
          SizedBox(
            width: w,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(t.value,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: t.color, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  Text(t.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

class _BetTile extends StatelessWidget {
  const _BetTile({required this.bet, required this.fmt, required this.onTap, required this.onSettle});
  final Bet bet;
  final Fmt fmt;
  final VoidCallback onTap;
  final void Function(BetStatus) onSettle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = BankColors.forStatus(context, bet.status);
    final pending = bet.status == BetStatus.pending;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bet.selection, style: theme.textTheme.titleSmall),
                  if (bet.event.isNotEmpty) Text(bet.event, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      Fmt.date(bet.date),
                      bet.sport,
                      if (bet.book.isNotEmpty) bet.book,
                      '${fmt.money(bet.stake)} @ ${formatOdds(bet.odds, fmt.settings.oddsFormat)}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(99)),
                  child: Text(bet.status.label.toUpperCase(),
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                ),
                const SizedBox(height: 6),
                if (pending)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _SettleButton(label: 'Won', color: BankColors.win(context), onTap: () => onSettle(BetStatus.won)),
                    const SizedBox(width: 6),
                    _SettleButton(label: 'Lost', color: BankColors.loss(context), onTap: () => onSettle(BetStatus.lost)),
                  ])
                else
                  Text(fmt.money(bet.profit, sign: true),
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: BankColors.forValue(context, bet.profit), fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ]),
        ),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your betting ledger starts here', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Set your starting bankroll from the settings icon, then log each bet with its stake and odds. '
                'Bank Track works out your balance, profit, ROI and win rate, and charts them as you settle bets.'),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Log your first bet')),
          ]),
        ),
      );
}
