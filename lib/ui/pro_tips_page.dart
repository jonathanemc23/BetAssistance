import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/store.dart';
import '../logic/pro_tips.dart';
import '../logic/stats.dart';
import 'format.dart';
import 'matches_screen.dart';

/// Gold used across Pro tips, whatever the app theme.
final _gold = [Color(0xFFF7D774), Color(0xFFE0A93B), Color(0xFFB9772A)];
final _onGold = Color(0xFF2A1A05);

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
            gradient: LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: _gold[1].withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 2))],
          ),
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome, size: 16, color: _onGold),
                SizedBox(width: 5),
                Text(tr('Pro tips'), style: TextStyle(color: _onGold, fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the Pro tips page for [match]. With [api] the page reads the
/// match's details itself when [details] is missing.
Future<void> openProTips(BuildContext context,
        {required BankStore store, required Match match, MatchDetails? details, FixturesApi? api, int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProTipsPage(store: store, match: match, details: details, api: api, initialTab: tab),
    ));

/// The tips for [m] as the app shows them everywhere: the simulated ones,
/// with the Pro tips already bought in their place.
MatchTips tipsFor(BankStore store, Match m, [MatchDetails? details]) =>
    simulateTips(m, details ?? MatchDetails.statusOf(m)).withBought(store.boughtTips(m.id));

/// The match's predictions: free Daily tips, and Pro tips unlocked with tokens.
class ProTipsPage extends StatefulWidget {
  const ProTipsPage({super.key, required this.store, required this.match, this.details, this.api, this.initialTab = 0});
  final BankStore store;
  final Match match;
  final MatchDetails? details;
  final FixturesApi? api;
  final int initialTab;

  @override
  State<ProTipsPage> createState() => _ProTipsPageState();
}

class _ProTipsPageState extends State<ProTipsPage> {
  late MatchDetails _details = widget.details ?? MatchDetails.statusOf(widget.match);

  (int, int)? get _score {
    final d = _details, m = widget.match;
    if ((d.state == MatchState.finished || m.state == MatchState.finished)) {
      final h = d.homeScore ?? int.tryParse(m.home.score ?? ''), a = d.awayScore ?? int.tryParse(m.away.score ?? '');
      if (h != null && a != null) return (h, a);
    }
    return null;
  }

  /// Tips can be bought until kick-off.
  bool get _open => widget.match.state == MatchState.scheduled && _details.state != MatchState.live;

  @override
  void initState() {
    super.initState();
    _settle();
    final api = widget.api;
    if (widget.details == null && api != null) {
      // The form and table behind each tip; the tips themselves don't change.
      api.details(widget.match).then((d) {
        if (!mounted) return;
        setState(() => _details = d);
        _settle();
      }, onError: (Object _) {});
    }
  }

  void _settle() {
    if (_score case (final h, final a)) widget.store.settleTips(tipsFor(widget.store, widget.match, _details).pro, h, a);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final tips = tipsFor(widget.store, widget.match, _details);
          return Scaffold(
            appBar: AppBar(
              title: Text(tr('Pro tips')),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TokenChip(store: widget.store),
                ),
              ],
            ),
            body: Column(children: [
              _Teams(match: widget.match, score: _score),
              const _ProTabBar(),
              Expanded(
                child: TabBarView(children: [
                  _DailyTab(store: widget.store, tips: tips, score: _score),
                  _ProTab(store: widget.store, tips: tips, score: _score, open: _open),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _ProTabBar extends StatelessWidget {
  const _ProTabBar();

  @override
  Widget build(BuildContext context) => TabBar(tabs: [
        Tab(text: tr('Daily tips')),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium, size: 18),
          SizedBox(width: 6),
          Text(tr('Pro tips')),
        ])),
      ]);
}

/// The token balance; opens the wallet.
class TokenChip extends StatelessWidget {
  const TokenChip({super.key, required this.store});
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showTokensSheet(context, store),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const TokenCoin(size: 20),
            const SizedBox(width: 6),
            Text('${store.tokens}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        ),
      ),
    );
  }
}

/// A gold token.
class TokenCoin extends StatelessWidget {
  const TokenCoin({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: _gold, begin: Alignment.topLeft, end: Alignment.bottomRight),
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
                        ? tr('Full time')
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

/// One line naming a tip's match: crests, teams, kick-off and league. Opens
/// the match's own tips when tapped.
class TipMatchLine extends StatelessWidget {
  const TipMatchLine({super.key, required this.match, this.onTap});
  final Match match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    final when = m.state == MatchState.live ? tr('Live') : DateFormat.Hm().format(m.kickoff.toLocal());
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          TeamLogo(url: m.home.logo, name: m.home.name, size: 20),
          const SizedBox(width: 2),
          TeamLogo(url: m.away.logo, name: m.away.name, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('$when · ${m.league.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Daily tips

class _DailyTab extends StatelessWidget {
  const _DailyTab({required this.store, required this.tips, required this.score});
  final BankStore store;
  final MatchTips tips;
  final (int, int)? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = tips.pro.length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      ProTipsPromo(
        text: trn(n, '{n} expert pick for this match with the reasons behind them. If a Pro tip loses, your tokens come back.',
            '{n} expert picks for this match with the reasons behind them. If a Pro tip loses, your tokens come back.'),
        onTap: () => DefaultTabController.of(context).animateTo(1),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(tr('FREE TODAY'), style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
      ),
      if (tips.daily.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No free tips for this match.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final t in tips.daily) TipCard(tip: t, store: store, score: score),
      const _PreviewNote(),
    ]);
  }
}

/// The banner that sells Pro tips, on the Daily tips tabs and Home.
class ProTipsPromo extends StatelessWidget {
  const ProTipsPromo({super.key, required this.text, required this.onTap, this.heading});

  /// The heading; the general one when null.
  final String? heading;
  String get title => heading ?? tr('Get our full bet analysis');
  final String text;
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
                    gradient: LinearGradient(colors: _gold),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tr('PRO TIPS'),
                      style: TextStyle(color: _onGold, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
                const SizedBox(height: 10),
                Text(title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in Confidence.values) LevelPill(level: c, dark: true),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _gold),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('See Pro tips'), style: TextStyle(color: _onGold, fontWeight: FontWeight.w900)),
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
        tr('Preview: tips are simulated while our prediction model is being built. Bet responsibly.'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ---------------------------------------------------------------- Pro tips

/// How Pro tips are priced, under the token balance.
String get proRulesText => tr('The more a Pro tip costs, the better its odds: Max (3 tokens) from 1.80 to 2.00, High (2 tokens) and Medium (1 token) from 1.60 to 2.00. Free tips go from 1.40 to 2.00. If a Pro tip loses, the tokens go back to your balance.');

/// The token balance with the Get tokens button and the pricing rules.
class _Wallet extends StatelessWidget {
  const _Wallet({required this.store});
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const TokenCoin(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trn(store.tokens, '{n} token', '{n} tokens'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              Text(tr('Your balance'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          FilledButton.tonal(onPressed: () => showTokensSheet(context, store), child: Text(tr('Get tokens'))),
        ]),
        const SizedBox(height: 12),
        Text(proRulesText, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _ProTab extends StatelessWidget {
  const _ProTab({required this.store, required this.tips, required this.score, required this.open});
  final BankStore store;
  final MatchTips tips;
  final (int, int)? score;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      _Wallet(store: store),
      const SizedBox(height: 16),
      if (tips.pro.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No Pro tips for this match yet.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final t in tips.pro) TipCard(tip: t, store: store, score: score, onBuy: open ? () => buyTip(context, store, t) : null),
      const _PreviewNote(),
    ]);
  }
}

/// Asks, then spends tokens on [t]; opens the wallet when there aren't enough.
Future<void> buyTip(BuildContext context, BankStore store, Tip t) async {
  if (store.tokens < t.cost) {
    await showTokensSheet(context, store, need: t.cost);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const TokenCoin(size: 36),
      title: Text(tr('Buy this {level} tip?', {'level': t.level.title})),
      content: Text(trn(t.cost, 'It costs {n} token of your {tokens}. If the tip loses, you get it back.',
          'It costs {n} tokens of your {tokens}. If the tip loses, you get them back.', {'tokens': store.tokens})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Buy prediction'))),
      ],
    ),
  );
  if (ok != true) return;
  if (await store.unlockTip(t) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Unlocked: {pick}', {'pick': trPick(t.pick)}))));
  }
}

/// The colour of a confidence level.
Color levelColor(Confidence c) => switch (c) {
      Confidence.max => const Color(0xFFE0A93B),
      Confidence.high => const Color(0xFF4FB286),
      Confidence.medium => const Color(0xFF5E9BD6),
    };

/// Small label for a confidence level with its price.
class LevelPill extends StatelessWidget {
  const LevelPill({super.key, required this.level, this.dark = false, this.showCost = true});
  final Confidence level;
  final bool dark;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: dark ? 0.25 : 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(level.title.toUpperCase(),
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

class _FreePill extends StatelessWidget {
  const _FreePill();

  @override
  Widget build(BuildContext context) {
    final c = BankColors.win(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Text(tr('FREE'), style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
    );
  }
}

/// A small fact about a tip, such as its odds.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: '$label ', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        TextSpan(
            text: value,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: color)),
      ])),
    );
  }
}

/// One prediction. Locked Pro tips show their odds and value but keep the
/// pick blurred behind a buy button. With [match] the card names the match
/// and opens its tips from that line.
class TipCard extends StatelessWidget {
  const TipCard({super.key, required this.tip, required this.store, this.score, this.onBuy, this.match, this.onOpenMatch});
  final Tip tip;
  final BankStore store;
  final (int, int)? score;
  final VoidCallback? onBuy;
  final Match? match;
  final VoidCallback? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = levelColor(tip.level);
    final unlocked = store.isUnlocked(tip);
    final settled = store.unlockedTips[tip.id]?.result;
    final won = tip.result(score?.$1, score?.$2);
    final format = store.settings.oddsFormat;

    final facts = Wrap(spacing: 6, runSpacing: 6, children: [
      _Fact(tip.isCombo ? tr('Combined odds') : tr('Odds'), formatOdds(tip.odds, format)),
      _Fact(tr('Value'), '+${(tip.value * 100).round()}%', color: BankColors.win(context)),
    ]);

    final pick = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tip.isCombo ? tr('Bet builder') : trPick(tip.pick),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
      if (tip.isCombo)
        for (final l in tip.legs)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.check_circle_outline, size: 16, color: level),
              const SizedBox(width: 6),
              Expanded(child: Text(trPick(l.pick), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              Text(formatOdds(l.odds, format), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
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
      const SizedBox(height: 8),
      facts,
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
    final locked = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      facts,
      const SizedBox(height: 10),
      Stack(alignment: Alignment.center, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Locked prediction pick'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Container(height: 8, decoration: BoxDecoration(color: level, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 10),
            Text(tr('Analysis of form, table and prices behind this pick for the match.')),
            Text(tr('More reasons from our model.')),
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
              label: Text(trn(tip.cost, 'Buy prediction · {n} token', 'Buy prediction · {n} tokens'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
            child: Text(tr('Sales closed at kick-off'), style: TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
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
        if (match != null) ...[
          TipMatchLine(match: match!, onTap: onOpenMatch),
          Divider(height: 14, color: cs.outlineVariant),
        ],
        Row(children: [
          Expanded(
            // The market stays hidden on a locked tip: with the odds it would
            // give the pick away.
            child: Text(unlocked ? tip.group.toUpperCase() : tr('PRO TIP'),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: cs.onSurfaceVariant)),
          ),
          if (unlocked && won != null) ...[
            _Result(won: won, refunded: settled == 'refunded', cost: tip.cost),
            const SizedBox(width: 6),
          ],
          if (tip.free) const _FreePill() else LevelPill(level: tip.level),
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
    final text = won ? tr('Won') : refunded ? tr('Lost · {n} refunded', {'n': cost}) : tr('Lost');
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
                const TokenCoin(size: 56),
                const SizedBox(height: 10),
                Text(trn(store.tokens, '{n} token', '{n} tokens'),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  need != null && store.tokens < need
                      ? trn(need, 'This tip needs {n} token.', 'This tip needs {n} tokens.')
                      : tr('Tokens are the money inside the app: use them to unlock Pro tips and buy bets in Community.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
                  child: Text(tr('Token packs are coming soon.'),
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => store.addTokens(5),
                    icon: const Icon(Icons.add),
                    label: Text(tr('Add 5 free test tokens')),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

// ---------------------------------------------------------------- Pro tips hub

/// Opens the Pro tips page for the whole day, on [tab] (1 is Pro tips).
Future<void> openProTipsHub(BuildContext context,
        {required BankStore store, required FixturesApi api, DateTime? today, int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProTipsHub(store: store, api: api, today: today, initialTab: tab),
    ));

/// Pro tips for the day, from Bet Tools and Home: free tips and Pro tips for
/// the important matches, and a search for any other match.
class ProTipsHub extends StatefulWidget {
  const ProTipsHub({super.key, required this.store, required this.api, this.today, this.initialTab = 0});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;
  final int initialTab;

  @override
  State<ProTipsHub> createState() => _ProTipsHubState();
}

class _ProTipsHubState extends State<ProTipsHub> {
  List<Match>? _matches;
  String? _error;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _error = null);
    try {
      final list = await widget.api.featuredMatches(_today, refresh: refresh);
      if (mounted) setState(() => _matches = list);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _open(Match m, {int tab = 0}) =>
      openProTips(context, store: widget.store, match: m, api: widget.api, tab: tab);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(tr('Pro tips')),
            actions: [Padding(padding: const EdgeInsets.only(right: 12), child: TokenChip(store: widget.store))],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _SearchButton(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _MatchSearch(store: widget.store, api: widget.api, day: _today, onOpen: _open),
                )),
              ),
            ),
            const _ProTabBar(),
            Expanded(child: _body()),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    final list = _matches;
    if (list == null) {
      if (_error == null) return const Center(child: CircularProgressIndicator());
      return _HubMessage(
        icon: Icons.cloud_off,
        text: _error!,
        action: FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
      );
    }
    // Tips are sold until kick-off.
    final open = [for (final m in list) if (m.state == MatchState.scheduled) m];
    final tips = {for (final m in open) m: tipsFor(widget.store, m)};
    return TabBarView(children: [
      RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _HubDaily(store: widget.store, tips: tips, onOpen: _open),
      ),
      RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: _HubPro(store: widget.store, tips: tips, onOpen: (m) => _open(m, tab: 1)),
      ),
    ]);
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        key: const Key('search-match'),
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Icon(Icons.search, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('Search a match'),
                  style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Icon(Icons.auto_awesome, size: 18, color: _gold[1]),
          ]),
        ),
      ),
    );
  }
}

class _HubMessage extends StatelessWidget {
  const _HubMessage({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Free tips for the day's important matches, under the Pro tips promo.
class _HubDaily extends StatelessWidget {
  const _HubDaily({required this.store, required this.tips, required this.onOpen});
  final BankStore store;
  final Map<Match, MatchTips> tips;
  final void Function(Match) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pro = tips.values.fold<int>(0, (n, t) => n + t.pro.length);
    final free = [
      for (final e in tips.entries)
        if (e.value.daily.isNotEmpty) (e.key, e.value.daily.first),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      ProTipsPromo(
        heading: tr("Today's best value bets"),
        text: trn(pro, "{n} expert pick for {matches} of today's big matches. If a Pro tip loses, your tokens come back.",
            "{n} expert picks for {matches} of today's big matches. If a Pro tip loses, your tokens come back.",
            {'matches': tips.length}),
        onTap: () => DefaultTabController.of(context).animateTo(1),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(tr("RECOMMENDED FOR TODAY'S BIG MATCHES"),
            style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
      ),
      if (free.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No big matches left today. Search a match to see its tips.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final (m, t) in free) TipCard(tip: t, store: store, match: m, onOpenMatch: () => onOpen(m)),
      const _PreviewNote(),
    ]);
  }
}

/// Pro tips for the day's important matches, match by match.
class _HubPro extends StatelessWidget {
  const _HubPro({required this.store, required this.tips, required this.onOpen});
  final BankStore store;
  final Map<Match, MatchTips> tips;
  final void Function(Match) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final withPro = [for (final e in tips.entries) if (e.value.pro.isNotEmpty) e];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      _Wallet(store: store),
      const SizedBox(height: 16),
      if (withPro.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No Pro tips left for today. Search a match to see its tips.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final e in withPro)
        for (final t in e.value.pro)
          TipCard(
            tip: t,
            store: store,
            match: e.key,
            onOpenMatch: () => onOpen(e.key),
            onBuy: () => buyTip(context, store, t),
          ),
      const _PreviewNote(),
    ]);
  }
}

/// Every match of the day, filtered as you type; a match opens its tips.
class _MatchSearch extends StatefulWidget {
  const _MatchSearch({required this.store, required this.api, required this.day, required this.onOpen});
  final BankStore store;
  final FixturesApi api;
  final DateTime day;
  final void Function(Match) onOpen;

  @override
  State<_MatchSearch> createState() => _MatchSearchState();
}

class _MatchSearchState extends State<_MatchSearch> {
  final _query = TextEditingController();
  var _sport = Sport.soccer;
  List<Match>? _all;
  String? _error;

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
    final sport = _sport;
    try {
      final list = await widget.api.matchesOn(widget.day, sport: sport);
      if (mounted && sport == _sport) setState(() => _all = list);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _plain(String s) => plainText(s).trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = _plain(_query.text);
    final list = [
      for (final m in _all ?? const <Match>[])
        if (q.isEmpty || _plain('${m.home.name} ${m.away.name} ${m.league.name}').contains(q)) m,
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Search a team or league'), border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: tr('Clear'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(_query.clear),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<Sport>(
              showSelectedIcon: false,
              segments: [
                for (final s in Sport.values)
                  ButtonSegment(value: s, label: FittedBox(fit: BoxFit.scaleDown, child: Text('${s.emoji} ${s.title}'))),
              ],
              selected: {_sport},
              onSelectionChanged: (v) {
                setState(() => _sport = v.first);
                _load();
              },
            ),
          ),
        ),
        Expanded(
          child: _all == null
              ? (_error == null
                  ? const Center(child: CircularProgressIndicator())
                  : _HubMessage(
                      icon: Icons.cloud_off,
                      text: _error!,
                      action: FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
                    ))
              : list.isEmpty
                  ? _HubMessage(
                      icon: Icons.search_off,
                      text: q.isEmpty ? tr('No matches today.') : tr('No match today for "{query}".', {'query': _query.text}),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (context, i) => TipMatchLine(match: list[i], onTap: () => widget.onOpen(list[i])),
                    ),
        ),
      ]),
    );
  }
}
