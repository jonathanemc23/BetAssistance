import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/store.dart';
import '../logic/pro_tips.dart';
import 'format.dart';
import 'matches_screen.dart';

/// Gold used across Pro tips, whatever the app theme.
const _gold = [Color(0xFFF7D774), Color(0xFFE0A93B), Color(0xFFB9772A)];
const _onGold = Color(0xFF2A1A05);

/// The "Pro tips" button at the top of the match page.
class ProTipsButton extends StatelessWidget {
  const ProTipsButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: _gold[1].withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: InkWell(
            onTap: onPressed,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 16, color: _onGold),
                SizedBox(width: 5),
                Text('Pro tips', style: TextStyle(color: _onGold, fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Pro tips page for [match].
Future<void> openProTips(BuildContext context,
        {required BankStore store, required Match match, required MatchDetails? details}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProTipsPage(store: store, match: match, details: details ?? MatchDetails.statusOf(match)),
    ));

/// The match's predictions: free Daily tips, and Pro tips unlocked with tokens.
class ProTipsPage extends StatefulWidget {
  const ProTipsPage({super.key, required this.store, required this.match, required this.details});
  final BankStore store;
  final Match match;
  final MatchDetails details;

  @override
  State<ProTipsPage> createState() => _ProTipsPageState();
}

class _ProTipsPageState extends State<ProTipsPage> {
  late final MatchTips _tips = simulateTips(widget.match, widget.details);

  (int, int)? get _score {
    final d = widget.details, m = widget.match;
    if ((d.state == MatchState.finished || m.state == MatchState.finished)) {
      final h = d.homeScore ?? int.tryParse(m.home.score ?? ''), a = d.awayScore ?? int.tryParse(m.away.score ?? '');
      if (h != null && a != null) return (h, a);
    }
    return null;
  }

  /// Tips can be bought until kick-off.
  bool get _open => widget.match.state == MatchState.scheduled && widget.details.state != MatchState.live;

  @override
  void initState() {
    super.initState();
    if (_score case (final h, final a)) widget.store.settleTips(_tips.pro, h, a);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Pro tips'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _TokenChip(tokens: widget.store.tokens, onTap: () => showTokensSheet(context, widget.store)),
              ),
            ],
          ),
          body: Column(children: [
            _Teams(match: widget.match, score: _score),
            const TabBar(tabs: [
              Tab(text: 'Daily tips'),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium, size: 18),
                SizedBox(width: 6),
                Text('Pro tips'),
              ])),
            ]),
            Expanded(
              child: TabBarView(children: [
                _DailyTab(tips: _tips, score: _score),
                _ProTab(store: widget.store, tips: _tips, score: _score, open: _open),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.tokens, required this.onTap});
  final int tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const _Coin(size: 20),
            const SizedBox(width: 6),
            Text('$tokens', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

/// A gold token.
class _Coin extends StatelessWidget {
  const _Coin({this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: _gold[2], width: 1),
        ),
        child: Text('T', style: TextStyle(color: _onGold, fontSize: size * 0.55, fontWeight: FontWeight.w900)),
      );
}

/// Both teams across the top, with the kick-off time or the final score.
class _Teams extends StatelessWidget {
  const _Teams({required this.match, required this.score});
  final Match match;
  final (int, int)? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    Widget side(Team t) => Expanded(
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: TeamLogo(url: t.logo, name: t.name, size: 42),
            ),
            const SizedBox(height: 6),
            Text(t.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.surfaceContainerHigh, cs.surfaceContainer],
        ),
        border: Border.all(color: _gold[1].withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        side(m.home),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(children: [
            Text(score == null ? 'VS' : '${score!.$1} - ${score!.$2}',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                score == null
                    ? DateFormat('EEE d MMM · HH:mm').format(m.kickoff.toLocal())
                    : m.state == MatchState.finished
                        ? 'Full time'
                        : m.detail,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(m.league.name,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        side(m.away),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Daily tips

class _DailyTab extends StatelessWidget {
  const _DailyTab({required this.tips, required this.score});
  final MatchTips tips;
  final (int, int)? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      _Promo(count: tips.pro.length, onTap: () => DefaultTabController.of(context).animateTo(1)),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('FREE TODAY', style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
      ),
      if (tips.daily.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No free tips for this match.',
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final t in tips.daily) _TipCard(tip: t, unlocked: true, score: score),
      const _PreviewNote(),
    ]);
  }
}

/// The banner at the top of Daily tips that sells the Pro tips tab.
class _Promo extends StatelessWidget {
  const _Promo({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1B1A12), Color(0xFF3B2F12), Color(0xFF6B4D16)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Positioned(
              right: -18,
              top: -18,
              child: Icon(Icons.auto_awesome, size: 110, color: _gold[0].withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _gold),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('PRO TIPS',
                      style: TextStyle(color: _onGold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
                const SizedBox(height: 10),
                Text('Get our full bet analysis',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  '$count expert pick${count == 1 ? '' : 's'} for this match with the reasons behind them. '
                  "If a Pro tip loses, your tokens come back.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in Confidence.values) _LevelPill(level: c, dark: true),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _gold),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('See Pro tips', style: TextStyle(color: _onGold, fontWeight: FontWeight.w900)),
                    Icon(Icons.chevron_right, color: _onGold),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PreviewNote extends StatelessWidget {
  const _PreviewNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Preview: tips are simulated while our prediction model is being built. '
        'Bet responsibly.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------- Pro tips

class _ProTab extends StatelessWidget {
  const _ProTab({required this.store, required this.tips, required this.score, required this.open});
  final BankStore store;
  final MatchTips tips;
  final (int, int)? score;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const _Coin(size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${store.tokens} token${store.tokens == 1 ? '' : 's'}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                Text('Your balance', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            FilledButton.tonal(onPressed: () => showTokensSheet(context, store), child: const Text('Get tokens')),
          ]),
          const SizedBox(height: 12),
          Text(
            'Each Pro tip costs tokens by how sure we are: '
            '${[for (final c in Confidence.values) '${c.label} ${c.cost}'].join(', ')}. '
            'If the tip loses, the tokens go back to your balance.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (tips.pro.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No Pro tips for this match yet.',
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final t in tips.pro)
        _TipCard(
          tip: t,
          unlocked: store.isUnlocked(t),
          score: score,
          settled: store.unlockedTips[t.id]?.result,
          onBuy: open ? () => _buy(context, t) : null,
        ),
      const _PreviewNote(),
    ]);
  }

  Future<void> _buy(BuildContext context, Tip t) async {
    if (store.tokens < t.cost) {
      await showTokensSheet(context, store, need: t.cost);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const _Coin(size: 36),
        title: Text('Buy this ${t.confidence.label} tip?'),
        content: Text('It costs ${t.cost} token${t.cost == 1 ? '' : 's'} of your ${store.tokens}. '
            'If the tip loses, you get ${t.cost == 1 ? 'it' : 'them'} back.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buy prediction')),
        ],
      ),
    );
    if (ok != true) return;
    if (await store.unlockTip(t) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unlocked: ${t.pick}')));
    }
  }
}

/// Small label for a confidence level with its price.
class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.level, this.dark = false, this.showCost = true});
  final Confidence level;
  final bool dark;
  final bool showCost;

  static Color colorOf(Confidence c) => switch (c) {
        Confidence.max => const Color(0xFFE0A93B),
        Confidence.high => const Color(0xFF4FB286),
        Confidence.medium => const Color(0xFF5E9BD6),
      };

  @override
  Widget build(BuildContext context) {
    final c = colorOf(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.25 : 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(level.label.toUpperCase(),
            style: TextStyle(
                color: dark ? Colors.white : c, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
        if (showCost) ...[
          const SizedBox(width: 4),
          Text('· ${level.cost}', style: TextStyle(color: dark ? Colors.white70 : c, fontSize: 10.5)),
        ],
      ]),
    );
  }
}

/// One prediction. Locked Pro tips keep the pick blurred behind a buy button.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.unlocked, required this.score, this.settled, this.onBuy});
  final Tip tip;
  final bool unlocked;
  final (int, int)? score;

  /// 'won' or 'refunded' for a paid tip once the match is over.
  final String? settled;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = _LevelPill.colorOf(tip.confidence);
    final won = tip.result(score?.$1, score?.$2);

    final pick = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tip.pick, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: tip.chance,
              minHeight: 8,
              color: level,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${tip.percent}%', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: level)),
      ]),
      const SizedBox(height: 4),
      Text('Fair odds ${tip.fairOdds.toStringAsFixed(2)}',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      for (final r in tip.reasons)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(width: 5, height: 5, decoration: BoxDecoration(color: level, shape: BoxShape.circle)),
            ),
            Expanded(child: Text(r, style: theme.textTheme.bodySmall)),
          ]),
        ),
    ]);

    // Placeholder text under the blur, so the real pick is never on screen.
    final locked = Stack(alignment: Alignment.center, children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Locked prediction pick', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Container(height: 8, decoration: BoxDecoration(color: level, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 10),
          const Text('Analysis of form, table and prices behind this pick for the match.'),
          const Text('More reasons from our model.'),
        ]),
      ),
      if (onBuy != null)
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: _gold[1].withValues(alpha: 0.4), blurRadius: 12)],
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _gold[1], foregroundColor: _onGold),
            onPressed: onBuy,
            icon: const Icon(Icons.lock_open, size: 18),
            label: Text('Buy prediction · ${tip.cost} token${tip.cost == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        )
      else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
          child: const Text('Sales closed at kick-off', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
    ]);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: level, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(tip.market.group.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant)),
          ),
          if (unlocked && won != null) ...[
            _Result(won: won, refunded: settled == 'refunded', cost: tip.cost),
            const SizedBox(width: 6),
          ],
          if (tip.free)
            _LevelPill(level: tip.confidence, showCost: false)
          else
            _LevelPill(level: tip.confidence),
        ]),
        const SizedBox(height: 8),
        if (unlocked) pick else locked,
      ]),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.won, required this.refunded, required this.cost});
  final bool won;
  final bool refunded;
  final int cost;

  @override
  Widget build(BuildContext context) {
    final c = won ? BankColors.win(context) : BankColors.loss(context);
    final text = won ? 'Won' : refunded ? 'Lost · $cost refunded' : 'Lost';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(won ? Icons.check_circle : Icons.undo, size: 12, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// The wallet: balance and how to get more tokens. Buying tokens isn't open
/// yet, so it offers free test tokens meanwhile.
Future<void> showTokensSheet(BuildContext context, BankStore store, {int? need}) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const _Coin(size: 56),
                const SizedBox(height: 10),
                Text('${store.tokens} token${store.tokens == 1 ? '' : 's'}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  need != null && store.tokens < need
                      ? 'This tip needs $need token${need == 1 ? '' : 's'}.'
                      : 'Tokens are the money inside the app: use them to unlock Pro tips.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
                  child: Text('Token packs are coming soon.',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => store.addTokens(5),
                    icon: const Icon(Icons.add),
                    label: const Text('Add 5 free test tokens'),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
