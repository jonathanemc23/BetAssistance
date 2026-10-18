import 'package:flutter/material.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/bet_review.dart';
import '../logic/stats.dart';
import 'format.dart';
import 'match_page.dart';
import 'themes.dart';

Future<void> openBetReview(
  BuildContext context, {
  required BankStore store,
  required FixturesApi api,
  required Bet bet,
  BetReviewer? reviewer,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => BetReviewPage(store: store, api: api, betId: bet.id, bet: bet, reviewer: reviewer),
  ),
);

/// Review bet: the bet, what changed since it was placed, the price check,
/// form, suggestions and the user's record on similar bets.
class BetReviewPage extends StatefulWidget {
  const BetReviewPage({
    super.key,
    required this.store,
    required this.api,
    required this.bet,
    this.betId,
    this.reviewer,
  });
  final BankStore store;
  final FixturesApi api;
  final Bet bet;
  final int? betId;
  final BetReviewer? reviewer;

  @override
  State<BetReviewPage> createState() => _BetReviewPageState();
}

class _BetReviewPageState extends State<BetReviewPage> {
  Future<BetReview>? _review;

  BankStore get store => widget.store;
  Bet get _bet => store.bets.where((b) => b.id != null && b.id == widget.betId).firstOrNull ?? widget.bet;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final country = countryByCode(await store.pref('matches.country'));
    final reviewer = widget.reviewer ?? DataBetReviewer(widget.api, country: country);
    if (!mounted) return;
    setState(() {
      _review = reviewer.review(_bet, history: store.bets, stats: store.stats, settings: store.settings);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bet review'),
        actions: [IconButton(tooltip: 'Review again', icon: const Icon(Icons.refresh), onPressed: _run)],
      ),
      body: FutureBuilder<BetReview>(
        future: _review,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text("Couldn't review this bet right now. Try again.", textAlign: TextAlign.center),
              ),
            );
          }
          return ListenableBuilder(listenable: store, builder: (context, _) => _body(snap.data!));
        },
      ),
    );
  }

  Widget _body(BetReview r) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = _bet;
    final hero = HeroColors.of(context);
    final fg = hero.onGradient;
    final fmt = Fmt(store.settings);
    final color = BankColors.forStatus(context, b.status);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: hero.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.isParlay ? '${b.legs.length}-leg parlay' : b.selection,
                      style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    formatOdds(b.odds, store.settings.oddsFormat),
                    style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              if (b.event.isNotEmpty)
                Text(b.event, style: theme.textTheme.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.85))),
              const SizedBox(height: 10),
              Text(
                r.headline,
                style: theme.textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${fmt.money(b.stake)} staked · ${b.status.label}',
                style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
        if (r.suggestedResult != null && b.status == BetStatus.pending) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => store.settle(b, r.suggestedResult!),
            icon: const Icon(Icons.check),
            label: Text('Mark as ${r.suggestedResult!.label.toLowerCase()}'),
          ),
        ] else if (b.status != BetStatus.pending) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Settled as ${b.status.label.toLowerCase()} · ${fmt.money(b.profit, sign: true)}',
                  style: theme.textTheme.labelLarge?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ],
        for (final s in r.sections) ...[const SizedBox(height: 14), _SectionCard(section: s)],
        if (r.match != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MatchPage(match: r.match!, store: store, api: widget.api),
              ),
            ),
            icon: const Icon(Icons.sports_soccer),
            label: const Text('Open the match page'),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Built from the match data and your own history. It is a guide, not a guarantee.',
          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final ReviewSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = section;
    final accent = switch (s.tone) {
      ReviewTone.good => BankColors.win(context),
      ReviewTone.warning => BankColors.pending(context),
      ReviewTone.neutral => cs.primary,
    };
    final icon = switch (s.kind) {
      'bet' => Icons.receipt_long_outlined,
      'updates' => Icons.update,
      'market' => Icons.trending_up,
      'context' => Icons.insights_outlined,
      'suggestions' => Icons.lightbulb_outline,
      'record' => Icons.history,
      _ => Icons.notes,
    };
    final bullets = s.kind == 'suggestions' || s.kind == 'updates';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final l in s.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bullets)
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Icon(Icons.circle, size: 5, color: cs.onSurfaceVariant),
                    ),
                  Expanded(child: Text(l, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
