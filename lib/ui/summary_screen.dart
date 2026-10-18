import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'bank_screens.dart';
import 'format.dart';

/// Main page: bankroll control and the key numbers, nothing else.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key, required this.store, required this.onLogBet, required this.onOpenBets});
  final BankStore store;
  final VoidCallback onLogBet;
  final VoidCallback onOpenBets;

  void _toast(BuildContext context, String? msg) {
    if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(store.settings);
    final s = store.stats;
    final theme = Theme.of(context);
    final types = countByType(store.bets);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      BankCard(store: store, fmt: fmt, stats: s, onToast: (m) => _toast(context, m)),
      const SizedBox(height: 12),
      KpiGrid(tiles: [
        Kpi('Profit / loss', fmt.money(s.profit, sign: true),
            '${s.units >= 0 ? '+' : '−'}${s.units.abs().toStringAsFixed(1)} units', BankColors.forValue(context, s.profit)),
        Kpi('ROI', fmt.pct(s.roi), 'on ${fmt.money(s.turnover)} staked', BankColors.forValue(context, s.roi)),
        Kpi('Win rate', '${(s.winRate * 100).toStringAsFixed(0)}%', '${s.wins}W · ${s.losses}L', null),
        Kpi('Bets', '${s.count}', '${s.settledCount} settled · ${s.pendingCount} open', null),
        Kpi('Avg odds', s.avgOdds == 0 ? '–' : formatOdds(s.avgOdds, store.settings.oddsFormat), 'won and lost bets', null),
        Kpi('At risk', fmt.money(s.exposure), '${s.pendingCount} open bets', null),
      ]),
      if (store.bets.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              for (final t in BetType.values)
                Expanded(
                  child: Column(children: [
                    Text('${types[t] ?? 0}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                    Text(t.label, style: theme.textTheme.bodySmall),
                  ]),
                ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onOpenBets,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Bet register'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(onPressed: onLogBet, icon: const Icon(Icons.add), label: const Text('Log bet')),
        ),
      ]),
    ]);
  }
}

class BankCard extends StatelessWidget {
  const BankCard({super.key, required this.store, required this.fmt, required this.stats, required this.onToast});
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

class Kpi {
  const Kpi(this.label, this.value, this.sub, this.color);
  final String label, value, sub;
  final Color? color;
}

class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});
  final List<Kpi> tiles;

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
