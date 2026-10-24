import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/pro_tips.dart';
import '../logic/stats.dart';
import 'format.dart';
import 'match_page.dart';
import 'matches_screen.dart';
import 'pro_tips_page.dart';
import 'profile.dart';
import 'summary_screen.dart';
import 'themes.dart';

/// Gold used for Pro tips, whatever the app theme.
const _gold = [Color(0xFFF7D774), Color(0xFFE0A93B), Color(0xFFB9772A)];
const _onGold = Color(0xFF2A1A05);

/// The first tab: who you are and where your bank stands, then the day's
/// important matches, Pro tips and free tips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.api,
    required this.onLogBet,
    required this.onOpenBets,
    required this.onOpenMatches,
    this.today,
  });
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;
  final VoidCallback onLogBet;
  final VoidCallback onOpenBets;
  final VoidCallback onOpenMatches;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Match>? _matches;
  String? _error;

  BankStore get store => widget.store;
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

  void _openSummary() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Summary')),
          body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => SummaryScreen(
              store: store,
              onLogBet: widget.onLogBet,
              onOpenBets: () {
                Navigator.of(context).pop();
                widget.onOpenBets();
              },
            ),
          ),
        ),
      ));

  void _openMatch(Match m) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => MatchPage(match: m, store: store, api: widget.api)));

  void _openHub(int tab) => openProTipsHub(context, store: store, api: widget.api, today: _today, tab: tab);

  void _openTips(Match m, {int tab = 0}) => openProTips(context, store: store, match: m, api: widget.api, tab: tab);

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    // Tips are sold until kick-off.
    final open = [for (final m in matches ?? const <Match>[]) if (m.state == MatchState.scheduled) m];
    final tips = [for (final m in open) (m, tipsFor(store, m))];
    final pro = [
      for (final (m, t) in tips)
        if (t.pro.isNotEmpty) (m, t.pro.first),
    ];
    final free = [
      for (final (m, t) in tips)
        if (t.daily.isNotEmpty) (m, t.daily.first),
    ].take(4).toList();

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _HomeHeader(store: store, onSummary: _openSummary, onLogBet: widget.onLogBet, onOpenBets: widget.onOpenBets),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Important matches today', action: 'All matches', onAction: widget.onOpenMatches),
        SizedBox(
          height: 156,
          child: matches == null
              ? _StripMessage(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text("Couldn't load today's matches. Try again"),
                        ),
                )
              : matches.isEmpty
                  ? const _StripMessage(child: Text('No big matches left today.'))
                  : ListView.separated(
                      key: const Key('home-matches'),
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => _MatchBox(
                        match: matches[i],
                        format: store.settings.oddsFormat,
                        onTap: () => _openMatch(matches[i]),
                      ),
                    ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(title: 'Pro tips', action: 'See all', onAction: () => _openHub(1), gold: true),
        _ProBanner(count: pro.length, tokens: store.tokens, onTap: () => _openHub(1)),
        if (pro.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              key: const Key('home-pro-tips'),
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: pro.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _ProTipBox(
                match: pro[i].$1,
                tip: pro[i].$2,
                store: store,
                onTap: () => _openTips(pro[i].$1, tab: 1),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _SectionTitle(title: 'Free tips', action: 'More', onAction: () => _openHub(0)),
        if (matches != null && free.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No free tips left for today.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        for (final (m, t) in free)
          _FreeTipRow(match: m, tip: t, format: store.settings.oddsFormat, onTap: () => _openTips(m)),
        if (free.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Preview: tips are simulated while our prediction model is being built. Bet responsibly.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}

/// Avatar and greeting, the bank, a few highlights and the way to the full
/// summary.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.store, required this.onSummary, required this.onLogBet, required this.onOpenBets});
  final BankStore store;
  final VoidCallback onSummary;
  final VoidCallback onLogBet;
  final VoidCallback onOpenBets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = HeroColors.of(context);
    final fg = hero.onGradient;
    final fmt = Fmt(store.settings);
    final s = store.stats;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 19 ? 'Good afternoon' : 'Good evening';
    final openParlays = store.parlays.where((p) => p.isOpen).length;

    Widget chip(IconData icon, String text, {VoidCallback? onTap}) => Material(
          color: fg.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
                Text(text, style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: hero.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: hero.gradient.first.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InkWell(
            key: const Key('home-avatar'),
            customBorder: const CircleBorder(),
            onTap: () => showAvatarPicker(context, store),
            child: ProfileAvatar(store: store, size: 56),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting, style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8))),
              Text(store.profileName.isEmpty ? 'Welcome back' : store.profileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text('BANK', style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8), letterSpacing: 1.2)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(fmt.money(s.balance),
                  style: theme.textTheme.headlineMedium?.copyWith(
                      color: fg, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          const SizedBox(width: 8),
          Text('${fmt.money(s.available)} available',
              style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8))),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 6, runSpacing: 6, children: [
          chip(Icons.receipt_long, '${s.pendingCount} open bet${s.pendingCount == 1 ? '' : 's'}', onTap: onOpenBets),
          if (s.exposure > 0) chip(Icons.hourglass_bottom, '${fmt.money(s.exposure)} at risk'),
          chip(s.profit >= 0 ? Icons.trending_up : Icons.trending_down, 'P/L ${fmt.money(s.profit, sign: true)}'),
          chip(Icons.percent, 'ROI ${fmt.pct(s.roi)}'),
          if (openParlays > 0) chip(Icons.account_tree_outlined, '$openParlays open parlay${openParlays == 1 ? '' : 's'}'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: hero.gradient.first),
              onPressed: onSummary,
              icon: const Icon(Icons.dashboard_outlined, size: 18),
              label: const Text('See summary', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.6))),
              onPressed: onLogBet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Log bet'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction, this.gold = false});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(children: [
        if (gold) ...[Icon(Icons.auto_awesome, size: 18, color: _gold[1]), const SizedBox(width: 6)],
        Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        if (action != null)
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onAction,
            child: Text(action!),
          ),
      ]),
    );
  }
}

class _StripMessage extends StatelessWidget {
  const _StripMessage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

/// One important match in the strip: league, both teams, kick-off or the
/// live score, and the 1X2 prices.
class _MatchBox extends StatelessWidget {
  const _MatchBox({required this.match, required this.format, required this.onTap});
  final Match match;
  final OddsFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    final live = m.state == MatchState.live;
    final odds = m.odds;
    Widget team(Team t) => Row(children: [
          Container(
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
            child: TeamLogo(url: t.logo, name: t.name, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (m.hasScore)
            Text(t.score ?? '-',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: live ? cs.error : null)),
        ]);
    return SizedBox(
      width: 200,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primaryContainer, cs.surfaceContainerHigh],
            ),
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(m.league.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.8, color: cs.onSurfaceVariant)),
                  ),
                  if (live)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(6)),
                      child: Text('LIVE ${m.detail}',
                          style: TextStyle(color: cs.onError, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    )
                  else
                    Text(DateFormat.Hm().format(m.kickoff.toLocal()),
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
                ]),
                const Spacer(),
                team(m.home),
                const SizedBox(height: 6),
                team(m.away),
                const Spacer(),
                if (odds != null && !odds.isEmpty)
                  Row(children: [
                    for (final (label, price) in [('1', odds.home), ('X', odds.draw), ('2', odds.away)])
                      if (price != null)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            decoration: BoxDecoration(
                                color: cs.surface.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '$label ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
                                TextSpan(
                                    text: formatOdds(price, format),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                              ]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                  ])
                else
                  Text(m.venue ?? m.league.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gold strip that leads to the day's Pro tips.
class _ProBanner extends StatelessWidget {
  const _ProBanner({required this.count, required this.tokens, required this.onTap});
  final int count;
  final int tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              const TokenCoin(size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Value bets for today', style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  Text(
                    count == 0
                        ? 'Expert picks with the reasons behind them. You have $tokens tokens.'
                        : '$count big match${count == 1 ? '' : 'es'} with Pro picks at odds of 1.80+. You have $tokens tokens.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(gradient: LinearGradient(colors: _gold), shape: BoxShape.circle),
                child: const Icon(Icons.chevron_right, color: _onGold, size: 20),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One Pro tip in the strip: its match, level, odds and value; the pick
/// only once bought.
class _ProTipBox extends StatelessWidget {
  const _ProTipBox({required this.match, required this.tip, required this.store, required this.onTap});
  final Match match;
  final Tip tip;
  final BankStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unlocked = store.isUnlocked(tip);
    final level = levelColor(tip.level);
    return SizedBox(
      width: 220,
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _gold[1].withValues(alpha: 0.55)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                LevelPill(level: tip.level),
                const Spacer(),
                Text(formatOdds(tip.odds, store.settings.oddsFormat),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: level)),
              ]),
              const SizedBox(height: 8),
              Text(match.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('${DateFormat.Hm().format(match.kickoff.toLocal())} · ${match.league.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              if (unlocked)
                Text(tip.pick,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))
              else
                Row(children: [
                  Flexible(
                    child: Text('Value +${(tip.value * 100).round()}%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: BankColors.win(context), fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: _gold),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_open, size: 14, color: _onGold),
                      const SizedBox(width: 4),
                      Text('${tip.cost}',
                          style: const TextStyle(color: _onGold, fontWeight: FontWeight.w900, fontSize: 12)),
                      const SizedBox(width: 3),
                      const TokenCoin(size: 14),
                    ]),
                  ),
                ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One free tip: match, pick, odds and chance.
class _FreeTipRow extends StatelessWidget {
  const _FreeTipRow({required this.match, required this.tip, required this.format, required this.onTap});
  final Match match;
  final Tip tip;
  final OddsFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final level = levelColor(tip.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              TeamLogo(url: match.home.logo, name: match.home.name, size: 22),
              const SizedBox(width: 2),
              TeamLogo(url: match.away.logo, name: match.away.name, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tip.pick,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${match.title} · ${DateFormat.Hm().format(match.kickoff.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatOdds(tip.odds, format),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                Text('${tip.percent}%', style: theme.textTheme.labelSmall?.copyWith(color: level, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
