import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/store.dart';
import 'community.dart';
import 'parlay_screens.dart';
import 'pro_tips_page.dart';
import 'stake_builder.dart';
import 'themes.dart';

/// Bet Tools tab: the helpers for studying matches and building bets.
class BetToolsScreen extends StatelessWidget {
  const BetToolsScreen({super.key, required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final open = store.parlays.where((p) => p.isOpen).length;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          Text(tr('Study a match, build a parlay, then log it.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          _ToolCard(
            icon: Icons.auto_awesome,
            title: tr('Pro tips'),
            text: tr("Value bets for today's big matches, free daily tips, and a search for any other match."),
            badge: trn(store.tokens, '{n} token', '{n} tokens'),
            highlight: true,
            onTap: () => openProTipsHub(context, store: store, api: api, today: today),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.account_tree_outlined,
            title: tr('Parlay builder'),
            text: tr('Combine picks from the match list or any other match, check them, share them and track the result.'),
            badge: open == 0 ? null : tr('{n} open', {'n': open}),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => ParlaysPage(store: store, api: api))),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.query_stats,
            title: tr('Stake builder'),
            text: tr('Goals, corners, cards and shots for any match. Pick the stats you like from one or more matches and validate the stake.'),
            badge: store.stake.isEmpty ? null : trn(store.stake.length, '{n} pick', '{n} picks'),
            onTap: () => openStakeBuilder(context, store: store, api: api, today: today),
          ),
          const SizedBox(height: 12),
          _ToolCard(
            icon: Icons.groups_2_outlined,
            title: tr('Community'),
            text: tr('Buy bets from pro bettors, or take the pro bettor challenge to sell your own.'),
            onTap: () => openCommunity(context, store: store, api: api, today: today),
          ),
        ]);
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
    this.badge,
    this.highlight = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final String? badge;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hero = HeroColors.of(context);
    final fg = highlight ? hero.onGradient : cs.onSurface;
    final sub = highlight ? hero.onGradient.withValues(alpha: 0.8) : cs.onSurfaceVariant;
    return Material(
      color: highlight ? Colors.transparent : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: highlight
            ? BoxDecoration(
                gradient: LinearGradient(colors: hero.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight))
            : null,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: highlight ? fg.withValues(alpha: 0.14) : cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: highlight ? fg : cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: fg)),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: highlight ? fg.withValues(alpha: 0.16) : cs.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(badge!,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: highlight ? fg : cs.primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(text, style: theme.textTheme.bodySmall?.copyWith(color: sub)),
                ]),
              ),
              Icon(Icons.chevron_right, color: sub),
            ]),
          ),
        ),
      ),
    );
  }
}
