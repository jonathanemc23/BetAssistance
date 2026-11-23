import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
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
final _gold = [Color(0xFFF7D774), Color(0xFFE0A93B), Color(0xFFB9772A)];
final _onGold = Color(0xFF2A1A05);

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

  /// The day the strip and the tips are for: today, or the next day with
  /// big matches when today has none left.
  DateTime? _day;

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
      var day = _today;
      var list = await widget.api.featuredMatches(day, refresh: refresh);
      // Nothing left today: the next day with big matches, up to 3 days on.
      for (var i = 1; i <= 3 && list.isEmpty; i++) {
        day = DateTime(_today.year, _today.month, _today.day + i);
        list = await widget.api.featuredMatches(day, refresh: refresh);
      }
      if (list.isEmpty) day = _today;
      if (mounted) {
        setState(() {
          _matches = list;
          _day = day;
        });
      }
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _openSummary() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('Summary'))),
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


  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    // Tips are sold until kick-off.
    final open = [for (final m in matches ?? const <Match>[]) if (m.state == MatchState.scheduled) m];
    final tips = [for (final m in open) (m, tipsFor(store, m))];
    final pro = [
      for (final (m, t) in tips) ...[for (final p in t.pro) (m, p)],
    ];
    final free = freePicksOfTheDay([for (final (m, t) in tips) for (final d in t.daily) (m, d)]);
    final day = _day ?? _today;
    final later = day.year != _today.year || day.month != _today.month || day.day != _today.day;
    final dayName = DateFormat('EEEE d MMMM').format(day);

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        _HomeHeader(store: store, onSummary: _openSummary, onLogBet: widget.onLogBet, onOpenBets: widget.onOpenBets),
        const SizedBox(height: 22),
        if (later)
          Container(
            key: const Key('home-next-day'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(Icons.event_available, size: 18, color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('No big matches left today. Here are the picks for {day}.', {'day': dayName}),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer)),
              ),
            ]),
          ),
        _SectionTitle(
            title: later ? tr('Big matches on {day}', {'day': dayName}) : tr('Important matches today'),
            action: tr('All matches'),
            onAction: widget.onOpenMatches),
        SizedBox(
          height: 156,
          child: matches == null
              ? _StripMessage(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(tr("Couldn't load today's matches. Try again")),
                        ),
                )
              : matches.isEmpty
                  ? _StripMessage(child: Text(tr('No big matches left today.')))
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
        _SectionTitle(title: tr('Pro tips'), action: tr('See all'), onAction: () => _openHub(1), gold: true),
        _ProBanner(onTap: () => _openHub(1)),
        if (pro.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 214,
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
                onTap: () => openTipPage(context, store: store, match: pro[i].$1, tip: pro[i].$2, api: widget.api),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        _SectionTitle(
            title: later ? tr('BetPilot free picks for {day}', {'day': dayName}) : tr('BetPilot free picks for today'),
            action: tr('More'),
            onAction: () => _openHub(0)),
        if (matches != null && free.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(tr('No free tips left for today.'),
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        for (final (m, t) in free)
          _FreeTipRow(
              match: m,
              tip: t,
              format: store.settings.oddsFormat,
              onTap: () => openTipPage(context, store: store, match: m, tip: t, api: widget.api)),
        if (free.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('Picks read from real bookmaker prices, with their margin removed. Bet responsibly.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ]),
    );
  }
}

/// Avatar and greeting, the bank, a few highlights and the way to the full
/// summary. The bank is the money not riding on a bet: it drops when a bet
/// is placed, and the stakes of open bets show as "In play".
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
    final greeting = hour < 12
        ? tr('Good morning')
        : hour < 19
        ? tr('Good afternoon')
        : tr('Good evening');
    final openParlays = store.parlays.where((p) => p.isOpen).length;
    final muted = fg.withValues(alpha: 0.72);

    // One figure under the bank: a label over its value.
    Widget stat(String label, String value, {Color? color, Key? key}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 0.8, fontSize: 10),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: key,
              style: theme.textTheme.titleMedium?.copyWith(
                color: color ?? fg,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: fg.withValues(alpha: 0.18),
    );

    final good = Color.lerp(BankColors.win(context), fg, 0.35)!;
    final bad = Color.lerp(BankColors.loss(context), fg, 0.35)!;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: hero.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: hero.gradient.first.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          // Soft rings in the corner, for depth.
          Positioned(
            right: -50,
            top: -60,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: fg.withValues(alpha: 0.07), width: 26),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      key: const Key('home-avatar'),
                      customBorder: const CircleBorder(),
                      onTap: () => showAvatarPicker(context, store),
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: fg.withValues(alpha: 0.55), width: 2),
                        ),
                        child: ProfileAvatar(store: store, size: 52),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(greeting, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                          Text(
                            store.profileName.isEmpty ? tr('Welcome back') : store.profileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(tr('BANK'), style: theme.textTheme.labelSmall?.copyWith(color: muted, letterSpacing: 1.4)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          fmt.money(s.available),
                          key: const Key('home-bank'),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // What open bets have staked; opens the register.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Material(
                        color: fg.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: const Key('home-in-play'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: onOpenBets,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  tr('In play'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  fmt.money(s.exposure),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Text(
                                  [
                                    trn(s.pendingCount, '{n} open bet', '{n} open bets'),
                                    if (openParlays > 0) trn(openParlays, '{n} open parlay', '{n} open parlays'),
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(color: muted, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      stat(
                        tr('Profit'),
                        fmt.money(s.profit, sign: true),
                        color: s.profit > 0
                            ? good
                            : s.profit < 0
                            ? bad
                            : null,
                      ),
                      divider(),
                      stat(
                        'ROI',
                        fmt.pct(s.roi),
                        color: s.roi > 0
                            ? good
                            : s.roi < 0
                            ? bad
                            : null,
                      ),
                      divider(),
                      stat(tr('Hit rate'), s.wins + s.losses == 0 ? '-' : '${(s.winRate * 100).round()}%'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: fg,
                          foregroundColor: hero.gradient.first,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: onSummary,
                        icon: const Icon(Icons.dashboard_outlined, size: 18),
                        label: Text(tr('See summary'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: fg,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: fg.withValues(alpha: 0.6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: onLogBet,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr('Log bet'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
                      child: Text(tr('LIVE {clock}', {'clock': m.detail}),
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
  const _ProBanner({required this.onTap});
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
                  Text(tr('Bets with real value every day, with the best analysis from our model'),
                      style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                    tr('Choose between our High and Max levels of trust. Real odds of 1.80 or more.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final c in proLevels) LevelPill(level: c, dark: true),
                  ]),
                ]),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(gradient: LinearGradient(colors: _gold), shape: BoxShape.circle),
                child: Icon(Icons.chevron_right, color: _onGold, size: 20),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One Pro tip in the strip: both teams with their crests, the level, the
/// bet type, the odds and the chance; the pick only once bought. Opens the
/// tip's own page.
class _ProTipBox extends StatelessWidget {
  const _ProTipBox({required this.match, required this.tip, required this.store, required this.onTap});
  final Match match;
  final Tip tip;
  final BankStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fg = Colors.white;
    final unlocked = store.isUnlocked(tip);
    final level = levelColor(tip.level);
    Widget team(Team t) => Row(children: [
          Container(
            width: 26,
            height: 26,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95), shape: BoxShape.circle),
            child: TeamLogo(url: t.logo, name: t.name, size: 21),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
          ),
        ]);
    return SizedBox(
      width: 252,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF17160F), Color(0xFF2B2412)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold[1].withValues(alpha: 0.6)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  LevelPill(level: tip.level, dark: true, showCost: false),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${DateFormat.Hm().format(match.kickoff.toLocal())} · ${match.league.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
                  ),
                ]),
                const SizedBox(height: 10),
                team(match.home),
                const SizedBox(height: 5),
                team(match.away),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Text(unlocked ? trPick(tip.pick) : tip.group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: unlocked ? fg : Colors.white70, fontWeight: unlocked ? FontWeight.w800 : null)),
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tr('Odds')} ', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      TextSpan(
                          text: formatOdds(tip.odds, store.settings.oddsFormat),
                          style: TextStyle(color: _gold[0], fontSize: 18, fontWeight: FontWeight.w900)),
                    ]),
                  ),
                ]),
                Text(tr('{pct}% chance', {'pct': tip.percent}),
                    style: theme.textTheme.labelSmall?.copyWith(color: level, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (unlocked)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        border: Border.all(color: _gold[1]), borderRadius: BorderRadius.circular(20)),
                    child: Text(tr('See analysis'), style: TextStyle(color: _gold[0], fontWeight: FontWeight.w800, fontSize: 12.5)),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _gold),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: _gold[1].withValues(alpha: 0.35), blurRadius: 8)],
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.lock_open, size: 15, color: _onGold),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(tr('Unlock Pro analysis'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: _onGold, fontWeight: FontWeight.w900, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 6),
                      Text('${tip.cost}', style: TextStyle(color: _onGold, fontWeight: FontWeight.w900, fontSize: 12.5)),
                      const SizedBox(width: 3),
                      const TokenCoin(size: 15),
                    ]),
                  ),
              ]),
            ),
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
                  Text(trPick(tip.pick),
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
