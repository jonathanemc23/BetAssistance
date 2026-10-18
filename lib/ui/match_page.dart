import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'bet_form.dart';
import 'format.dart';
import 'market_sheet.dart';
import 'matchboard_screen.dart';
import 'matches_screen.dart';
import 'money_movement.dart';
import 'parlay_screens.dart';

/// One match: score header, then tabs for odds, money movement, news, teams, line-ups, key
/// events, stats, head-to-head and the league table (ESPN summary feed).
class MatchPage extends StatefulWidget {
  const MatchPage(
      {super.key, required this.match, required this.store, required this.api, this.onPick, this.initialTab = 0});
  final Match match;

  /// Tab to open on, an index into the tabs (1 is Money).
  final int initialTab;
  final BankStore store;
  final FixturesApi api;

  /// Set when picking for a parlay: a tapped price closes the page and goes here.
  final void Function(Match match, String selection, double odds)? onPick;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  MatchDetails? _details;
  String? _error;
  bool _loading = true;

  static const _tabs = ['Odds', 'Money', 'News', 'Teams', 'Line-ups', 'Events', 'Stats', 'H2H', 'Table'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.api.details(widget.match, refresh: refresh);
      if (mounted) setState(() => _details = d);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String selection, double odds) {
    final m = widget.match;
    if (widget.onPick != null) {
      Navigator.pop(context);
      widget.onPick!(m, selection, odds);
      return;
    }
    pickSelection(context, store: widget.store, api: widget.api, match: m, selection: selection, odds: odds);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return DefaultTabController(
      length: _tabs.length,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(m.league.name),
          actions: [
            FavoriteStar(store: widget.store, match: m),
            IconButton(
              tooltip: 'Open in Matchboard',
              icon: const Icon(Icons.space_dashboard_outlined),
              onPressed: () async {
                final board = await widget.store.openBoard(m);
                if (context.mounted) await openBoard(context, store: widget.store, api: widget.api, board: board);
              },
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openBetForm(context, widget.store, template: m.toBetTemplate()),
          icon: const Icon(Icons.add),
          label: const Text('Log a bet'),
        ),
        body: Column(children: [
          _Header(match: m, details: _details),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in _tabs) Tab(text: t)],
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    final d = _details;
    if (d == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _Empty(
        icon: Icons.cloud_off,
        text: _error ?? "Couldn't load this match.",
        action: FilledButton.tonal(onPressed: _load, child: const Text('Try again')),
      );
    }
    final fmt = widget.store.settings.oddsFormat;
    final m = widget.match;
    return TabBarView(children: [
      _OddsTab(match: m, details: d, format: fmt, onPick: _pick),
      MoneyMovementView(match: m, details: d, store: widget.store),
      _NewsTab(news: d.news),
      _TeamsTab(match: m, details: d),
      _LineupsTab(details: d),
      _EventsTab(match: m, details: d),
      _StatsTab(match: m, details: d),
      _H2HTab(details: d),
      _TableTab(match: m, details: d),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.match, required this.details});
  final Match match;
  final MatchDetails? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    final live = m.state == MatchState.live;
    Widget side(Team t, TeamInfo? info) => Expanded(
          child: Column(children: [
            TeamLogo(url: t.logo ?? info?.logo, name: t.name, size: 52),
            const SizedBox(height: 8),
            Text(t.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (info != null && info.record.isNotEmpty)
              Text(_wdl(info.record), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        );
    final centre = m.hasScore
        ? Text('${m.home.score ?? '-'}  –  ${m.away.score ?? '-'}',
            style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: live ? cs.error : null,
                fontFeatures: const [FontFeature.tabularFigures()]))
        : Text(DateFormat.Hm().format(m.kickoff.toLocal()),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800));
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.surfaceContainerHigh],
        ),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          side(m.home, details?.home),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(children: [
              centre,
              const SizedBox(height: 4),
              if (live)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(6)),
                  child: Text('LIVE ${m.detail}',
                      style: TextStyle(color: cs.onError, fontSize: 11, fontWeight: FontWeight.w800)),
                )
              else
                Text(m.state == MatchState.scheduled ? 'Kick-off' : m.detail,
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          side(m.away, details?.away),
        ]),
        const SizedBox(height: 10),
        Text(
          [DateFormat.yMMMEd().format(m.kickoff.toLocal()), if (m.venue != null) m.venue!].join(' · '),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

/// "6-2-4" -> "6W 2D 4L"
String _wdl(String record) {
  final p = record.split('-');
  return p.length == 3 ? '${p[0]}W ${p[1]}D ${p[2]}L' : record;
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});
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
          Icon(icon, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: theme.colorScheme.primary)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

ListView _list(List<Widget> children) =>
    ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: children);

// ---------------------------------------------------------------- Odds

class _OddsTab extends StatelessWidget {
  const _OddsTab({required this.match, required this.details, required this.format, required this.onPick});
  final Match match;
  final MatchDetails details;
  final OddsFormat format;
  final void Function(String selection, double odds) onPick;

  @override
  Widget build(BuildContext context) {
    final books = details.odds.isNotEmpty ? details.odds : [if (match.odds != null) match.odds!];
    final theme = Theme.of(context);
    final m = match;
    final more = OutlinedButton.icon(
      onPressed: () async {
        final pick = await showMarketSheet(context, event: m.title, format: format, askOdds: true);
        if (pick != null) onPick(pick.selection, pick.odds!);
      },
      icon: const Icon(Icons.list_alt),
      label: const Text('More markets: handicap, corners, cards…'),
    );
    return _list([
      if (books.isEmpty) ...[
        const SizedBox(height: 24),
        Icon(Icons.percent, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text('No bookmaker prices for this match yet. You can still add any market with your own odds.',
            textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ] else ...[
        Text('Tap a price to log it as a bet or add it to a parlay.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      more,
      const SizedBox(height: 10),
      for (final o in books)
        _Section(
          title: o.provider.isEmpty ? 'Odds' : o.provider,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (o.count > 0) ...[
              Text('Match result', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              OddsRow(
                odds: o,
                homeName: m.home.name,
                awayName: m.away.name,
                format: format,
                onPick: onPick,
                large: true,
              ),
            ],
            if (o.totalLine != null && (o.over != null || o.under != null)) ...[
              const SizedBox(height: 12),
              Text('Total goals ${_num(o.totalLine!)}', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(children: [
                if (o.over != null)
                  Expanded(
                    child: _PriceButton(
                      label: 'Over',
                      price: o.over!,
                      format: format,
                      onTap: () => onPick('Over ${_num(o.totalLine!)} goals', o.over!),
                    ),
                  ),
                if (o.over != null && o.under != null) const SizedBox(width: 8),
                if (o.under != null)
                  Expanded(
                    child: _PriceButton(
                      label: 'Under',
                      price: o.under!,
                      format: format,
                      onTap: () => onPick('Under ${_num(o.totalLine!)} goals', o.under!),
                    ),
                  ),
              ]),
            ],
            if (o.extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('More markets', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, price) in o.extras)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 32 - 28 - 8) / 2,
                    child: _PriceButton(
                      label: label.replaceFirst('Double chance ', ''),
                      price: price,
                      format: format,
                      onTap: () => onPick(_extraSelection(label, m), price),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
    ]);
  }

  static String _extraSelection(String label, Match m) => switch (label) {
        'Double chance 1X' => '${m.home.name} or draw',
        'Double chance 12' => '${m.home.name} or ${m.away.name}',
        'Double chance X2' => '${m.away.name} or draw',
        _ => label,
      };
}

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.label, required this.price, required this.format, required this.onTap});
  final String label;
  final double price;
  final OddsFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 4),
            Text(formatOdds(price, format),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- News

class _NewsTab extends StatelessWidget {
  const _NewsTab({required this.news});
  final List<NewsItem> news;

  @override
  Widget build(BuildContext context) {
    if (news.isEmpty) return const _Empty(icon: Icons.newspaper, text: 'No news for this match yet.');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _list([
      for (final n in news)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: cs.surfaceContainerLow,
          child: InkWell(
            onTap: n.url == null
                ? null
                : () => launchUrl(Uri.parse(n.url!), mode: LaunchMode.externalApplication),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (n.image != null)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(n.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: cs.surfaceContainerHighest)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.headline, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (n.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(n.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    if (n.published != null)
                      Text(DateFormat.yMMMd().add_Hm().format(n.published!.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    const Spacer(),
                    if (n.url != null) Icon(Icons.open_in_new, size: 16, color: cs.primary),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Teams

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    final teams = [(match.home, details.home), (match.away, details.away)];
    if (teams.every((t) => t.$2.form.isEmpty && t.$2.lastGames.isEmpty && t.$2.leaders.isEmpty && t.$2.record.isEmpty)) {
      return const _Empty(icon: Icons.groups, text: 'No team info for this match.');
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _list([
      for (final (t, info) in teams)
        _Section(
          title: t.name,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              TeamLogo(url: t.logo ?? info.logo, name: t.name, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(spacing: 16, runSpacing: 4, children: [
                  if (info.record.isNotEmpty) _Fact('Record', _wdl(info.record)),
                  if (info.points.isNotEmpty) _Fact('Points', info.points),
                  if (_position(info) case final pos?) _Fact('Position', pos),
                ]),
              ),
            ]),
            if (_form(info).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Form (latest first)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(children: [for (final r in _form(info).split('')) _FormChip(r)]),
            ],
            if (info.lastGames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Last matches', style: theme.textTheme.labelLarge),
              for (final g in info.lastGames.reversed) _GameRow(game: g, showResult: true),
            ],
            if (info.leaders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Top players', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final (cat, player, value) in info.leaders)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                        width: 110,
                        child: Text(cat, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                    Expanded(child: Text(player, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          ]),
        ),
    ]);
  }

  String? _position(TeamInfo info) {
    for (final r in details.table) {
      if ((info.id.isNotEmpty && r.teamId == info.id) || r.team == info.name) return '#${r.rank}';
    }
    return null;
  }

  /// ESPN's form string (newest first), else built from the last games,
  /// which ESPN lists oldest first.
  static String _form(TeamInfo info) => info.form.isNotEmpty
      ? info.form
      : info.lastGames.reversed.map((g) => g.result).where((r) => r.isNotEmpty).join();
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _FormChip extends StatelessWidget {
  const _FormChip(this.result);
  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'W' => BankColors.win(context),
      'L' => BankColors.loss(context),
      _ => BankColors.neutral(context),
    };
    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Text(result, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, this.showResult = false});
  final PastGame game;
  final bool showResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final g = game;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 54,
          child: Text(g.date == null ? '' : DateFormat('d MMM\nyyyy').format(g.date!.toLocal()),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Expanded(child: Text(g.home, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
          child: Text(g.score, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(child: Text(g.away, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (showResult && g.result.isNotEmpty) ...[const SizedBox(width: 6), _FormChip(g.result)],
      ]),
    );
  }
}

// ---------------------------------------------------------------- Line-ups

class _LineupsTab extends StatelessWidget {
  const _LineupsTab({required this.details});
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    final teams = [details.home, details.away];
    if (teams.every((t) => t.starters.isEmpty)) {
      return const _Empty(
          icon: Icons.format_list_numbered, text: 'Line-ups usually appear about an hour before kick-off.');
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget player(Player p) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: cs.secondaryContainer,
              child: Text(p.jersey,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (p.subbedIn) Icon(Icons.arrow_upward, size: 16, color: BankColors.win(context)),
            if (p.subbedOut) Icon(Icons.arrow_downward, size: 16, color: BankColors.loss(context)),
            const SizedBox(width: 6),
            SizedBox(
              width: 34,
              child: Text(p.position == 'SUB' ? '' : p.position,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ]),
        );
    return _list([
      for (final t in teams)
        if (t.starters.isNotEmpty)
          _Section(
            title: t.name,
            trailing: t.formation == null ? null : Text(t.formation!, style: theme.textTheme.labelLarge),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in t.starters) player(p),
              if (t.subs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Substitutes', style: theme.textTheme.labelLarge),
                for (final p in t.subs) player(p),
              ],
            ]),
          ),
    ]);
  }
}

// ---------------------------------------------------------------- Events

class _EventsTab extends StatelessWidget {
  const _EventsTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    final events = details.events.where((e) => e.kind != KeyEventKind.other).toList();
    if (events.isEmpty) return const _Empty(icon: Icons.timeline, text: 'Goals, cards and subs appear once the match starts.');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _list([
      for (final e in events)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 40,
              child: Text(e.clock,
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
            _EventIcon(e.kind),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (e.side != null)
                  Text(e.side == 'home' ? match.home.name : match.away.name,
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.primary)),
                Text(e.text,
                    style: e.kind == KeyEventKind.goal || e.kind == KeyEventKind.period
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : null),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _EventIcon extends StatelessWidget {
  const _EventIcon(this.kind);
  final KeyEventKind kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget card(Color c) => Container(
          width: 14,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        );
    return switch (kind) {
      KeyEventKind.goal => Icon(Icons.sports_soccer, size: 22, color: BankColors.win(context)),
      KeyEventKind.yellow => card(const Color(0xFFF2C230)),
      KeyEventKind.red => card(const Color(0xFFD9372B)),
      KeyEventKind.sub => Icon(Icons.swap_vert, size: 22, color: cs.primary),
      KeyEventKind.period => Icon(Icons.flag_outlined, size: 22, color: cs.outline),
      KeyEventKind.other => Icon(Icons.circle, size: 8, color: cs.outline),
    };
  }
}

// ---------------------------------------------------------------- Stats

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.stats.isEmpty) return const _Empty(icon: Icons.bar_chart, text: 'No stats for this match yet.');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _list([
      _Section(
        title: details.statsAreSeason ? 'Season so far' : 'Match stats',
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(match.home.shortName, style: theme.textTheme.labelLarge)),
            Expanded(child: Text(match.away.shortName, textAlign: TextAlign.right, style: theme.textTheme.labelLarge)),
          ]),
          const SizedBox(height: 8),
          for (final (label, h, a) in details.stats) ...[
            Row(children: [
              SizedBox(width: 56, child: Text(h, style: const TextStyle(fontWeight: FontWeight.w700))),
              Expanded(
                child: Text(_title(label),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              SizedBox(
                  width: 56,
                  child: Text(a, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            _CompareBar(home: _value(h), away: _value(a)),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    ]);
  }

  static double? _value(String v) => double.tryParse(v.replaceAll('%', '').replaceAll('+', ''));

  /// ESPN mixes "SHOTS" and "Corner Kicks"; show them alike.
  static String _title(String s) => s == s.toUpperCase() && s.length > 3 ? s[0] + s.substring(1).toLowerCase() : s;
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.home, required this.away});
  final double? home;
  final double? away;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = (home ?? 0).abs(), a = (away ?? 0).abs();
    final total = h + a;
    if (total == 0) return const SizedBox(height: 6);
    final hf = (h / total * 1000).round(), af = 1000 - hf;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(children: [
          if (hf > 0) Expanded(flex: hf, child: Container(color: cs.primary)),
          if (hf > 0 && af > 0) const SizedBox(width: 2),
          if (af > 0) Expanded(flex: af, child: Container(color: cs.tertiary)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- H2H

class _H2HTab extends StatelessWidget {
  const _H2HTab({required this.details});
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.h2h.isEmpty) {
      return const _Empty(icon: Icons.compare_arrows, text: 'No recent meetings between these teams.');
    }
    return _list([
      _Section(
        title: 'Head to head',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (details.h2hSummary.isNotEmpty) ...[
            Text(details.h2hSummary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
          ],
          for (final g in details.h2h) _GameRow(game: g),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Table

class _TableTab extends StatelessWidget {
  const _TableTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.table.isEmpty) return const _Empty(icon: Icons.table_rows, text: 'No league table for this competition.');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ids = {details.home.id, details.away.id}..remove('');
    final names = {match.home.name, match.away.name};
    TextStyle? head = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    Widget cell(String t, {double w = 28, TextStyle? style}) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: style));
    Widget row(List<Widget> cells, {bool highlight = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: highlight
              ? BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8))
              : null,
          child: Row(children: cells),
        );
    return _list([
      _Section(
        title: details.tableTitle.isEmpty ? 'Table' : details.tableTitle,
        child: Column(children: [
          row([
            cell('#', style: head),
            Expanded(child: Text('Team', style: head)),
            for (final h in ['P', 'W', 'D', 'L', 'GD']) cell(h, style: head),
            cell('Pts', w: 34, style: head),
          ]),
          for (final r in details.table)
            row(
              [
                cell('${r.rank}'),
                Expanded(child: Text(r.team, maxLines: 1, overflow: TextOverflow.ellipsis)),
                for (final v in [r.played, r.won, r.drawn, r.lost, r.goalDiff]) cell(v),
                cell(r.points, w: 34, style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
              highlight: ids.contains(r.teamId) || names.contains(r.team),
            ),
        ]),
      ),
    ]);
  }
}
