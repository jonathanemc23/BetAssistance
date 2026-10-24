import 'dart:math' as math;

import 'package:flutter/material.dart' hide KeyEvent, TableRow;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'bet_form.dart';
import 'format.dart';
import 'market_sheet.dart';
import 'match_visuals.dart';
import 'matches_screen.dart';
import 'money_movement.dart';
import 'parlay_screens.dart';
import 'pro_tips_page.dart';

/// One match: score header, then tabs for an overview, odds, money movement, stats with a
/// shot map, key events, line-ups, the league table, head-to-head, teams and news (ESPN
/// summary feed).
class MatchPage extends StatefulWidget {
  const MatchPage(
      {super.key, required this.match, required this.store, required this.api, this.onPick, this.initialTab = 0});
  final Match match;

  /// Tab to open on, an index into the tabs (2 is Money).
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

  static List<String> get _tabs => [
        tr('Overview'), tr('Odds'), tr('Money'), tr('Stats'), tr('Events'), //
        tr('Line-ups'), tr('Table'), tr('H2H'), tr('Teams'), tr('News'),
      ];

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
      _loadHistory(d);
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The last ten results and meetings, read after the page is up: the
  /// summary only has five results and this season's meetings.
  Future<void> _loadHistory(MatchDetails d) async {
    final h = await widget.api.history(widget.match, d);
    if (h != null && mounted && identical(_details, d)) setState(() => _details = d.withHistory(h));
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
            ProTipsButton(
              onPressed: () => openProTips(context, store: widget.store, match: m, details: _details, api: widget.api),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: tr('Refresh'),
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openBetForm(context, widget.store, template: m.toBetTemplate(), api: widget.api),
          icon: const Icon(Icons.add),
          label: Text(tr('Log a bet')),
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
        text: _error ?? tr("Couldn't load this match."),
        action: FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
      );
    }
    final fmt = widget.store.settings.oddsFormat;
    final m = widget.match;
    return TabBarView(children: [
      _OverviewTab(match: m, details: d, format: fmt),
      _OddsTab(match: m, details: d, format: fmt, onPick: _pick),
      MoneyMovementView(match: m, details: d, store: widget.store),
      _StatsTab(match: m, details: d),
      _EventsTab(match: m, details: d),
      _LineupsTab(match: m, details: d),
      _TableTab(match: m, details: d),
      _H2HTab(match: m, details: d),
      _TeamsTab(match: m, details: d),
      _NewsTab(news: d.news),
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
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: TeamLogo(url: t.logo ?? info?.logo, name: t.name, size: 48),
            ),
            const SizedBox(height: 8),
            Text(t.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (info != null && info.record.isNotEmpty)
              Text(_wdl(info.record), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        );
    final centre = m.hasScore
        ? Text('${m.home.score ?? '-'} - ${m.away.score ?? '-'}',
            style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: live ? cs.error : null,
                fontFeatures: const [FontFeature.tabularFigures()]))
        : Text(DateFormat.Hm().format(m.kickoff.toLocal()),
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900));
    final status = live
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.onError, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(tr('LIVE {clock}', {'clock': m.detail}), style: TextStyle(color: cs.onError, fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
            child: Text(m.state == MatchState.scheduled ? tr('Kick-off') : m.detail,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          );
    // Scorers and red cards under each team.
    final marks = (details?.events ?? const <KeyEvent>[])
        .where((e) => (e.kind == KeyEventKind.goal || e.kind == KeyEventKind.red) && e.side != null)
        .toList();
    Widget scorers(String sideName, CrossAxisAlignment align) => Expanded(
          child: Column(crossAxisAlignment: align, children: [
            for (final e in marks.where((e) => e.side == sideName))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (e.kind == KeyEventKind.goal)
                      Icon(Icons.sports_soccer, size: 12, color: cs.onSurfaceVariant)
                    else
                      Container(
                        width: 8,
                        height: 11,
                        decoration:
                            BoxDecoration(color: const Color(0xFFD9372B), borderRadius: BorderRadius.circular(2)),
                      ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('${_surname(e.player)} ${e.clock}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.surfaceContainerHigh, cs.surfaceContainer],
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          side(m.home, details?.home),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(children: [centre, const SizedBox(height: 6), status]),
          ),
          side(m.away, details?.away),
        ]),
        if (marks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            scorers('home', CrossAxisAlignment.center),
            const SizedBox(width: 24),
            scorers('away', CrossAxisAlignment.center),
          ]),
        ],
        const SizedBox(height: 10),
        Text(
          [
            DateFormat.yMMMEd().format(m.kickoff.toLocal()),
            if (m.venue != null) m.venue!,
            if (details?.attendance case final a? when a > 0) tr('{n} fans', {'n': NumberFormat.decimalPattern().format(a)}),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

/// "Bryan Mbeumo" -> "Mbeumo"; empty stays empty.
String _surname(String name) => name.trim().isEmpty ? '' : name.trim().split(' ').last;

/// "6-2-4" -> "6W 2D 4L"
String _wdl(String record) {
  final p = record.split('-');
  return p.length == 3 ? '${p[0]}${trForm('W')} ${p[1]}${trForm('D')} ${p[2]}${trForm('L')}' : record;
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

// ---------------------------------------------------------------- Overview

/// The match at a glance: win chances from the odds, key stats, the shot map,
/// both teams' form and where they sit in the table. Each part links to its tab.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.match, required this.details, required this.format});
  final Match match;
  final MatchDetails details;
  final OddsFormat format;

  // Tab indexes in [_MatchPageState._tabs].
  static const _statsTab = 3, _tableTab = 6, _teamsTab = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match, d = details;
    void open(int tab) => DefaultTabController.of(context).animateTo(tab);
    Widget more(String text, int tab) => Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => open(tab), child: Text(text)),
        );

    final book = [...d.odds, ?m.odds].where((o) => o.home != null && o.away != null).firstOrNull;
    final teams = [(m.home, d.home), (m.away, d.away)];
    final hasForm = teams.any((t) => t.$2.form.isNotEmpty || t.$2.lastGames.isNotEmpty);
    final liveStats = !d.statsAreSeason && StatTiles.any(d.statValues);
    final parts = <Widget>[
      if (book != null)
        _Section(
          title: tr('Win chances'),
          trailing: Text(book.provider, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          child: _WinChances(match: m, odds: book, format: format),
        ),
      if (liveStats)
        _Section(
          title: tr('Key stats'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StatTiles(values: d.statValues, max: 6),
            more(tr('All stats'), _statsTab),
          ]),
        ),
      if (d.shots.isNotEmpty)
        _Section(
          title: tr('Shot map'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ShotMap(shots: d.shots, home: m.home, away: m.away, compact: true),
            more(tr('Every shot'), _statsTab),
          ]),
        ),
      if (hasForm)
        _Section(
          title: tr('Form guide'),
          child: Column(children: [
            for (final (i, (t, inf)) in teams.indexed) ...[
              if (i == 1) Divider(height: 24, color: cs.outlineVariant),
              _FormGuideRow(team: t, info: inf, position: _position(inf), games: _TeamGame.of(t.name, inf)),
            ],
            more(tr('Latest results'), _teamsTab),
          ]),
        ),
      if (d.table.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(tr('TABLE'), style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
        ),
        StandingsTable(match: m, details: d, nearby: true),
        more(tr('Full table'), _tableTab),
      ],
    ];
    if (parts.isEmpty) {
      return _Empty(
        icon: Icons.info_outline,
        text: tr("This league's feed only has the kick-off time and score, so there are no stats, line-ups or table for this match."),
      );
    }
    return _list(parts);
  }

  String? _position(TeamInfo info) {
    for (final r in details.table) {
      if ((info.id.isNotEmpty && r.teamId == info.id) || r.team == info.name) return _ordinal(r.rank);
    }
    return null;
  }
}

/// The bookmaker's prices as chances: one bar split home, draw, away, with
/// the bookmaker's margin taken out.
class _WinChances extends StatelessWidget {
  const _WinChances({required this.match, required this.odds, required this.format});
  final Match match;
  final MatchOdds odds;
  final OddsFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final raw = [1 / odds.home!, if (odds.draw != null) 1 / odds.draw!, 1 / odds.away!];
    final sum = raw.fold<double>(0, (a, b) => a + b);
    final p = [for (final r in raw) r / sum];
    final hasDraw = odds.draw != null;
    final colors = [cs.primary, if (hasDraw) cs.outline, cs.tertiary];
    final labels = [match.home.shortName, if (hasDraw) tr('Draw'), match.away.shortName];
    final prices = [odds.home!, ?odds.draw, odds.away!];
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 12,
          child: Row(children: [
            for (final (i, v) in p.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(flex: (v * 1000).round().clamp(1, 1000), child: ColoredBox(color: colors[i], child: const SizedBox.expand())),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        for (final (i, v) in p.indexed)
          Expanded(
            child: Column(
              crossAxisAlignment: i == 0
                  ? CrossAxisAlignment.start
                  : i == p.length - 1
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.center,
              children: [
                Text('${(v * 100).round()}%',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: colors[i])),
                Text(labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text(formatOdds(prices[i], format), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
      ]),
    ]);
  }
}

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
      label: Text(tr('More markets: handicap, corners, cards…')),
    );
    return _list([
      if (books.isEmpty) ...[
        const SizedBox(height: 24),
        Icon(Icons.percent, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(tr('No bookmaker prices for this match yet. You can still add any market with your own odds.'),
            textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
      ] else ...[
        Text(tr('Tap a price to log it as a bet or add it to a parlay.'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
      more,
      const SizedBox(height: 10),
      for (final o in books)
        _Section(
          title: o.provider.isEmpty ? tr('Odds') : o.provider,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (o.count > 0) ...[
              Text(tr('Match result'), style: theme.textTheme.labelLarge),
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
              Text(tr('Total {unit} {line}', {'unit': trUnit(m.league.knownSport.scoreUnit), 'line': _num(o.totalLine!)}), style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(children: [
                if (o.over != null)
                  Expanded(
                    child: _PriceButton(
                      label: tr('Over'),
                      price: o.over!,
                      format: format,
                      onTap: () => onPick('Over ${_num(o.totalLine!)} ${m.league.knownSport.scoreUnit}', o.over!),
                    ),
                  ),
                if (o.over != null && o.under != null) const SizedBox(width: 8),
                if (o.under != null)
                  Expanded(
                    child: _PriceButton(
                      label: tr('Under'),
                      price: o.under!,
                      format: format,
                      onTap: () => onPick('Under ${_num(o.totalLine!)} ${m.league.knownSport.scoreUnit}', o.under!),
                    ),
                  ),
              ]),
            ],
            if (o.extras.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr('More markets'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, price) in o.extras)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 32 - 28 - 8) / 2,
                    child: _PriceButton(
                      label: trPick(label).replaceFirst('${tr('Double chance')} ', ''),
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
    if (news.isEmpty) return _Empty(icon: Icons.newspaper, text: tr('No news for this match yet.'));
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

class _TeamsTab extends StatefulWidget {
  const _TeamsTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  State<_TeamsTab> createState() => _TeamsTabState();
}

/// Recent results from one team's side: goals for and against, and W/D/L.
class _TeamGame {
  const _TeamGame(this.game, this.opponent, this.home, this.gf, this.ga, this.result);
  final PastGame game;
  final String opponent;
  final bool home;
  final int? gf, ga;
  final String result;

  static List<_TeamGame> of(String team, TeamInfo info) => [
        // ESPN lists the last games oldest first.
        for (final g in info.lastGames.reversed)
          () {
            final home = sameTeam(g.home, team) || (!sameTeam(g.away, team) && g.home == info.name);
            final s = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(g.score);
            final a = int.tryParse(s?.group(1) ?? ''), b = int.tryParse(s?.group(2) ?? '');
            final gf = home ? a : b, ga = home ? b : a;
            final result = g.result.isNotEmpty
                ? g.result
                : gf == null || ga == null
                    ? ''
                    : gf > ga
                        ? 'W'
                        : gf < ga
                            ? 'L'
                            : 'D';
            return _TeamGame(g, home ? g.away : g.home, home, gf, ga, result);
          }(),
      ];
}

class _TeamsTabState extends State<_TeamsTab> {
  int _side = 0;

  @override
  Widget build(BuildContext context) {
    final match = widget.match, details = widget.details;
    final teams = [(match.home, details.home), (match.away, details.away)];
    if (teams.every((t) => t.$2.form.isEmpty && t.$2.lastGames.isEmpty && t.$2.leaders.isEmpty && t.$2.record.isEmpty)) {
      return _Empty(icon: Icons.groups, text: tr('No team info for this match.'));
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (team, info) = teams[_side];
    final games = _TeamGame.of(team.name, info);
    return _list([
      _Section(
        title: tr('Form guide'),
        child: Column(children: [
          for (final (i, (t, inf)) in teams.indexed) ...[
            if (i == 1) Divider(height: 24, color: cs.outlineVariant),
            _FormGuideRow(team: t, info: inf, position: _position(inf), games: _TeamGame.of(t.name, inf)),
          ],
        ]),
      ),
      SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (final (i, (t, _)) in teams.indexed)
            ButtonSegment(value: i, label: Text(t.shortName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        selected: {_side},
        onSelectionChanged: (s) => setState(() => _side = s.first),
      ),
      const SizedBox(height: 12),
      if (games.isNotEmpty)
        _Section(
          title: tr('Latest results'),
          child: Column(children: [for (final g in games) _ResultRow(game: g)]),
        ),
      if (info.leaders.isNotEmpty)
        _Section(
          title: tr('Top players'),
          child: Column(children: [
            for (final (cat, player, value) in info.leaders)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(player, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                      Text(cat, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text(value,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }

  String? _position(TeamInfo info) {
    for (final r in widget.details.table) {
      if ((info.id.isNotEmpty && r.teamId == info.id) || r.team == info.name) return _ordinal(r.rank);
    }
    return null;
  }
}

String _ordinal(int n) {
  final s = (n % 100 >= 11 && n % 100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$s';
}

/// One team in the form guide: badge, table place, the last results as
/// chips and what they add up to.
class _FormGuideRow extends StatelessWidget {
  const _FormGuideRow({required this.team, required this.info, required this.position, required this.games});
  final Team team;
  final TeamInfo info;
  final String? position;
  final List<_TeamGame> games;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // The results listed below when they all have one, so the chips and the
    // goals add up; otherwise the feed's own form.
    final fromGames = games.isNotEmpty && games.every((g) => g.result.isNotEmpty);
    final form = fromGames || info.form.isEmpty ? games.map((g) => g.result).join() : info.form;
    final recent = form.length > 5 ? form.substring(0, 5) : form;
    final w = recent.split('').where((r) => r == 'W').length, d = recent.split('').where((r) => r == 'D').length;
    final scored = games.take(recent.length).where((g) => g.gf != null).toList();
    final gf = scored.fold<int>(0, (a, g) => a + g.gf!), ga = scored.fold<int>(0, (a, g) => a + g.ga!);
    final facts = [
      ?position,
      if (info.points.isNotEmpty) tr('{n} pts', {'n': info.points}),
      if (info.record.isNotEmpty) _wdl(info.record),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        TeamLogo(url: team.logo ?? info.logo, name: team.name, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (facts.isNotEmpty)
              Text(facts.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
      if (recent.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          for (final r in recent.split('')) Expanded(child: _FormBlock(r)),
        ]),
        const SizedBox(height: 6),
        Text(
          [
            tr('Last {n}: {pts} of {max} points', {'n': recent.length, 'pts': w * 3 + d, 'max': recent.length * 3}),
            if (scored.isNotEmpty) tr('scored {gf}, conceded {ga} in {n}', {'gf': gf, 'ga': ga, 'n': scored.length}),
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ]);
  }
}

/// A wide form chip; the newest result is on the left.
class _FormBlock extends StatelessWidget {
  const _FormBlock(this.result);
  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'W' => BankColors.win(context),
      'L' => BankColors.loss(context),
      _ => BankColors.neutral(context),
    };
    return Container(
      height: 30,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(trForm(result), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

/// One past game from the team's side: result, opponent, home or away, score.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.game});
  final _TeamGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final g = game;
    final sub = [
      if (g.game.date != null) DateFormat('d MMM').format(g.game.date!.toLocal()),
      g.home ? tr('Home') : tr('Away'),
      if (g.game.competition.isNotEmpty) g.game.competition,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        _FormChip(g.result.isEmpty ? '–' : g.result),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.home ? tr('vs {team}', {'team': g.opponent}) : tr('at {team}', {'team': g.opponent}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        Text(
          g.gf == null ? g.game.score : '${g.gf} – ${g.ga}',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
    );
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
      child: Text(trForm(result), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game, this.homeLogo, this.awayLogo});
  final PastGame game;
  final String? homeLogo, awayLogo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final g = game;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 50,
          child: Text(g.date == null ? '' : DateFormat('d MMM\nyyyy').format(g.date!.toLocal()),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        Expanded(child: Text(g.home, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        TeamLogo(url: homeLogo, name: g.home, size: 18),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Text(g.score,
              style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        TeamLogo(url: awayLogo, name: g.away, size: 18),
        const SizedBox(width: 6),
        Expanded(child: Text(g.away, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Line-ups

class _LineupsTab extends StatelessWidget {
  const _LineupsTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    final teams = [details.home, details.away];
    if (teams.every((t) => t.starters.isEmpty)) {
      return _Empty(
          icon: Icons.format_list_numbered, text: tr('Line-ups usually appear about an hour before kick-off.'));
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
    final pitch = LineupPitch.canDraw(details.home) && LineupPitch.canDraw(details.away);
    Widget formation(TeamInfo t, Color c, {bool end = false}) => Row(
          mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!end) ...[TeamLogo(url: t.logo, name: t.name, size: 22), const SizedBox(width: 6)],
            Flexible(
              child: Text('${t.name}  ${t.formation ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: c, fontWeight: FontWeight.w800)),
            ),
            if (end) ...[const SizedBox(width: 6), TeamLogo(url: t.logo, name: t.name, size: 22)],
          ],
        );
    return _list([
      if (pitch) ...[
        formation(details.away, cs.tertiary, end: true),
        const SizedBox(height: 6),
        LineupPitch(home: details.home, away: details.away),
        const SizedBox(height: 6),
        formation(details.home, cs.primary),
        const SizedBox(height: 16),
      ],
      for (final t in teams)
        if (t.starters.isNotEmpty)
          _Section(
            title: t.name,
            trailing: t.formation == null ? null : Text(t.formation!, style: theme.textTheme.labelLarge),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in t.starters) player(p),
              if (t.subs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('Substitutes'), style: theme.textTheme.labelLarge),
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
    if (events.isEmpty) return _Empty(icon: Icons.timeline, text: tr('Goals, cards and subs appear once the match starts.'));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // One side of the timeline: what happened, with the icon nearest the line.
    Widget detail(KeyEvent e, bool home) {
      final (title, sub) = switch (e.kind) {
        KeyEventKind.goal => (e.player.isEmpty ? tr('Goal') : e.player, tr('Goal')),
        KeyEventKind.yellow => (e.player.isEmpty ? tr('Yellow card') : e.player, tr('Yellow card')),
        KeyEventKind.red => (e.player.isEmpty ? tr('Red card') : e.player, tr('Red card')),
        KeyEventKind.sub => (
            e.player.isEmpty ? tr('Substitution') : e.player,
            e.playerOff.isEmpty ? tr('On') : tr('Off: {player}', {'player': e.playerOff})
          ),
        _ => (e.text, ''),
      };
      final goal = e.kind == KeyEventKind.goal;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: goal ? (home ? cs.primary : cs.tertiary).withValues(alpha: 0.16) : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          if (!home) ...[_EventIcon(e.kind), const SizedBox(width: 6)],
          Expanded(
            child: Column(crossAxisAlignment: home ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: home ? TextAlign.right : TextAlign.left,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: goal ? FontWeight.w800 : FontWeight.w600)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
          if (home) ...[const SizedBox(width: 6), _EventIcon(e.kind)],
        ]),
      );
    }

    return _list([
      Row(children: [
        Expanded(
          child: Row(children: [
            TeamLogo(url: match.home.logo ?? details.home.logo, name: match.home.name, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(match.home.shortName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: cs.primary)),
            ),
          ]),
        ),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Flexible(
              child: Text(match.away.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(color: cs.tertiary)),
            ),
            const SizedBox(width: 6),
            TeamLogo(url: match.away.logo ?? details.away.logo, name: match.away.name, size: 22),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      for (final e in events)
        if (e.side == null || e.kind == KeyEventKind.period)
          // Kick-off, half-time, full time: a divider across the timeline.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(child: Divider(color: cs.outlineVariant)),
              Flexible(
                flex: 4,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    [if (e.clock.isNotEmpty) e.clock, _periodLabel(e)].join(' · '),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: e.side == 'home' ? detail(e, true) : const SizedBox()),
                SizedBox(
                  width: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    VerticalDivider(width: 2, thickness: 2, color: cs.outlineVariant),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(e.clock,
                          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                Expanded(child: e.side == 'away' ? detail(e, false) : const SizedBox()),
              ]),
            ),
          ),
    ]);
  }

  /// "First Half begins." stays as the feed has it; empty texts get a name.
  static String _periodLabel(KeyEvent e) => e.text.isNotEmpty ? e.text : tr('Match event');
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

  static final _groups = [
    ('Attack', ['shot', 'on goal', 'on target', 'corner', 'offside', 'penalt', 'cross']),
    ('Passing', ['pass', 'long ball']),
    ('Defence', ['save', 'tackle', 'intercept', 'clearance', 'block']),
    ('Discipline', ['foul', 'card']),
  ];

  @override
  Widget build(BuildContext context) {
    if (details.stats.isEmpty) return _Empty(icon: Icons.bar_chart, text: tr('No stats for this match yet.'));
    final possession = details.stats.where((s) => s.$1.toLowerCase().contains('possession')).firstOrNull;
    final grouped = <String, List<(String, String, String)>>{};
    for (final (i, s) in details.stats.indexed) {
      if (identical(s, possession)) continue;
      // Tiles already show these.
      if (i < details.statNames.length && tileStatKeys.contains(details.statNames[i])) continue;
      final l = s.$1.toLowerCase();
      final g = _groups.where((g) => g.$2.any(l.contains)).firstOrNull?.$1 ?? 'Other';
      (grouped[g] ??= []).add(s);
    }
    return _list([
      _StatsHeader(match: match, details: details, possession: possession),
      if (StatTiles.any(details.statValues)) ...[
        StatTiles(values: details.statValues),
        const SizedBox(height: 12),
      ],
      if (details.shots.isNotEmpty)
        _Section(
          title: tr('Shot map'),
          child: ShotMap(shots: details.shots, home: match.home, away: match.away),
        )
      else if (!details.statsAreSeason && details.statValues['shotsOnTarget'] != null)
        _Section(
          title: tr('Shots'),
          child: _ShotCounts(match: match, details: details),
        ),
      for (final g in [..._groups.map((g) => g.$1), 'Other'])
        if (grouped[g] case final rows?)
          _Section(
            title: switch (g) {
              'Attack' => tr('Attack'),
              'Passing' => tr('Passing'),
              'Defence' => tr('Defence'),
              'Discipline' => tr('Discipline'),
              _ => tr('Other'),
            },
            child: Column(children: [for (final (label, h, a) in rows) _StatRow(label: trStat(_title(label)), home: h, away: a)]),
          ),
    ]);
  }

  static double? _value(String v) => statNumber(v);

  /// ESPN mixes "SHOTS" and "Corner Kicks"; show them alike.
  static String _title(String s) => s == s.toUpperCase() && s.length > 3 ? s[0] + s.substring(1).toLowerCase() : s;
}

/// Both crests, whether the numbers are this match or the season, and possession.
class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.match, required this.details, required this.possession});
  final Match match;
  final MatchDetails details;
  final (String, String, String)? possession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget team(Team t, TeamInfo info, Color c, {bool end = false}) => Row(
          mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!end) ...[TeamLogo(url: t.logo ?? info.logo, name: t.name, size: 26), const SizedBox(width: 8)],
            Flexible(
              child: Text(t.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c)),
            ),
            if (end) ...[const SizedBox(width: 8), TeamLogo(url: t.logo ?? info.logo, name: t.name, size: 26)],
          ],
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          Expanded(child: team(match.home, details.home, cs.primary)),
          Text(details.statsAreSeason ? tr('Season so far') : tr('This match'),
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          Expanded(child: team(match.away, details.away, cs.tertiary, end: true)),
        ]),
        if (possession case final p?) ...[
          const SizedBox(height: 14),
          _PossessionBar(home: _StatsTab._value(p.$2), away: _StatsTab._value(p.$3)),
        ],
      ]),
    );
  }
}

/// Shots on and off target when the feed has counts but not positions: each
/// team's goal with a filled circle per shot on target inside it and a hollow
/// one per miss around it.
class _ShotCounts extends StatelessWidget {
  const _ShotCounts({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    int n(String key, bool home) {
      final v = details.statValues[key];
      return (statNumber(home ? (v?.$1 ?? '') : (v?.$2 ?? '')) ?? 0).round();
    }

    Widget team(Team t, bool home) {
      final on = n('shotsOnTarget', home);
      final blocked = n('blockedShots', home);
      final off = (n('totalShots', home) - on - blocked).clamp(0, 40);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            [
              t.shortName,
              tr('{on} on target, {off} off target', {'on': on, 'off': off}) +
                  (blocked > 0 ? tr(', {n} blocked', {'n': blocked}) : ''),
            ].join(' · '),
            style: theme.textTheme.labelLarge?.copyWith(color: home ? cs.primary : cs.tertiary)),
        const SizedBox(height: 6),
        GoalMouth(shots: const [], onTarget: on, offTarget: off),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      team(match.home, true),
      const SizedBox(height: 12),
      team(match.away, false),
      const SizedBox(height: 10),
      const ShotLegend(),
      const SizedBox(height: 6),
      Text(tr("This league's feed gives shot counts but not where they were taken, so the circles are spread evenly."),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
    ]);
  }
}

/// Possession as one wide split bar with the shares written on it.
class _PossessionBar extends StatelessWidget {
  const _PossessionBar({required this.home, required this.away});
  final double? home, away;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = home ?? 0, a = away ?? 0;
    if (h + a == 0) return const SizedBox.shrink();
    final hf = (h / (h + a) * 1000).round();
    Widget part(int flex, Color bg, Color fg, String text, Alignment align) => Expanded(
          flex: flex,
          child: Container(
            height: 34,
            color: bg,
            alignment: align,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
          ),
        );
    String pct(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}%';
    return Column(children: [
      Text(tr('Possession'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Row(children: [
          if (hf > 0) part(hf, cs.primary, cs.onPrimary, pct(h), Alignment.centerLeft),
          if (hf < 1000) part(1000 - hf, cs.tertiary, cs.onTertiary, pct(a), Alignment.centerRight),
        ]),
      ),
    ]);
  }
}

/// One stat: both values with the leader highlighted, and bars that grow
/// out from the middle so the bigger side is obvious at a glance.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.home, required this.away});
  final String label, home, away;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = _StatsTab._value(home)?.abs() ?? 0, a = _StatsTab._value(away)?.abs() ?? 0;
    final max = h > a ? h : a;
    Widget value(String text, bool lead, Color color) => Container(
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: lead ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: lead ? (color == cs.primary ? cs.onPrimary : cs.onTertiary) : cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
    Widget bar(double v, Color color, bool fromRight) => Expanded(
          child: Align(
            alignment: fromRight ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: max == 0 ? 0 : (v / max).clamp(0.02, 1.0),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: v == max && v > 0 ? 1 : 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(children: [
        Row(children: [
          value(home, h > a, cs.primary),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          value(away, a > h, cs.tertiary),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          bar(h, cs.primary, true),
          const SizedBox(width: 4),
          bar(a, cs.tertiary, false),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- H2H

class _H2HTab extends StatelessWidget {
  const _H2HTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.h2h.isEmpty) {
      return _Empty(icon: Icons.compare_arrows, text: tr('No recent meetings between these teams.'));
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Wins for each side and draws, from the scores.
    var hw = 0, dr = 0, aw = 0;
    for (final g in details.h2h) {
      final s = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(g.score);
      final a = int.tryParse(s?.group(1) ?? ''), b = int.tryParse(s?.group(2) ?? '');
      if (a == null || b == null) continue;
      final homeFirst = sameTeam(g.home, match.home.name) || g.home == details.home.name;
      final (h, w) = homeFirst ? (a, b) : (b, a);
      if (h > w) {
        hw++;
      } else if (h < w) {
        aw++;
      } else {
        dr++;
      }
    }
    Widget tile(Widget top, int n, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              SizedBox(height: 30, child: Center(child: top)),
              const SizedBox(height: 4),
              Text('$n', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: c)),
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        );
    String? logo(String name) => sameTeam(name, match.home.name)
        ? match.home.logo ?? details.home.logo
        : sameTeam(name, match.away.name)
            ? match.away.logo ?? details.away.logo
            : null;
    return _list([
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(tr('LAST {n} MEETINGS', {'n': details.h2h.length}),
            style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
      ),
      Row(children: [
        tile(TeamLogo(url: match.home.logo ?? details.home.logo, name: match.home.name, size: 28), hw,
            tr('{team} wins', {'team': match.home.shortName}), cs.primary),
        const SizedBox(width: 8),
        tile(Icon(Icons.handshake_outlined, color: cs.onSurfaceVariant), dr, tr('Draws'), cs.outline),
        const SizedBox(width: 8),
        tile(TeamLogo(url: match.away.logo ?? details.away.logo, name: match.away.name, size: 28), aw,
            tr('{team} wins', {'team': match.away.shortName}), cs.tertiary),
      ]),
      const SizedBox(height: 12),
      _Section(
        title: tr('Head to head'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (details.h2hSummary.isNotEmpty) ...[
            Text(details.h2hSummary, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
          ],
          for (final g in details.h2h) _GameRow(game: g, homeLogo: logo(g.home), awayLogo: logo(g.away)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Table

class _TableTab extends StatefulWidget {
  const _TableTab({required this.match, required this.details});
  final Match match;
  final MatchDetails details;

  @override
  State<_TableTab> createState() => _TableTabState();
}

class _TableTabState extends State<_TableTab> {
  bool _around = false;

  @override
  Widget build(BuildContext context) {
    final details = widget.details, match = widget.match;
    if (details.table.isEmpty) return _Empty(icon: Icons.table_rows, text: tr('No league table for this competition.'));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mine = details.table.where((r) => _sideOf(r, match, details) != null).toList();

    return _list([
      if (mine.length == 2 && mine.every((r) => r.points.isNotEmpty))
        Row(children: [
          for (final (i, r) in mine.indexed) ...[
            if (i == 1) const SizedBox(width: 10),
            Expanded(child: _PlaceCard(row: r, home: _sideOf(r, match, details) == 'home')),
          ],
        ]),
      if (mine.length == 2 && mine.every((r) => r.points.isNotEmpty)) ...[
        const SizedBox(height: 8),
        Text(details.tableGroups.length > 1 ? _gapAcross(mine[0], mine[1]) : _gap(mine[0], mine[1]), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
      ],
      Row(children: [
        Expanded(
          child: Text((details.tableTitle.isEmpty ? tr('Table') : details.tableTitle).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
        ),
        if (mine.isNotEmpty)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: false, label: Text(tr('Full'))),
              ButtonSegment(value: true, label: Text(tr('Nearby'))),
            ],
            selected: {_around},
            onSelectionChanged: (s) => setState(() => _around = s.first),
          ),
      ]),
      const SizedBox(height: 8),
      StandingsTable(match: match, details: details, nearby: _around),
    ]);
  }

  /// The two teams compared on points when they play in different groups.
  static String _gapAcross(TableRow a, TableRow b) {
    final pa = int.tryParse(a.points), pb = int.tryParse(b.points);
    if (pa == null || pb == null || pa == pb) {
      return pa != null && pa == pb ? tr('In different groups, level on {n} points.', {'n': pa}) : tr('In different groups.');
    }
    final (top, other) = pa > pb ? (a, b) : (b, a);
    final diff = (pa - pb).abs();
    return trn(diff, 'In different groups. {top} have {n} point more than {other}.',
        'In different groups. {top} have {n} points more than {other}.', {'top': top.team, 'other': other.team});
  }

  /// How far apart the two teams are, in plain words.
  static String _gap(TableRow a, TableRow b) {
    final pa = int.tryParse(a.points), pb = int.tryParse(b.points);
    final places = (a.rank - b.rank).abs();
    if (pa == null || pb == null) return trn(places, '{n} place apart.', '{n} places apart.');
    if (pa == pb) return trn(places, 'Level on {pts} points, {n} place apart.', 'Level on {pts} points, {n} places apart.', {'pts': pa});
    final (top, other) = pa > pb ? (a, b) : (b, a);
    final diff = (pa - pb).abs();
    return trn(diff, '{top} lead {other} by {n} point.', '{top} lead {other} by {n} points.', {'top': top.team, 'other': other.team});
  }
}

/// 'home' or 'away' when [r] is one of the match's teams.
String? _sideOf(TableRow r, Match match, MatchDetails details) {
  if ((details.home.id.isNotEmpty && r.teamId == details.home.id) || r.team == match.home.name) return 'home';
  if ((details.away.id.isNotEmpty && r.teamId == details.away.id) || r.team == match.away.name) return 'away';
  return null;
}

/// One team's place: big ordinal, crest, points and goal difference.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.row, required this.home});
  final TableRow row;
  final bool home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = home ? cs.primary : cs.tertiary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        TeamLogo(url: row.logo, name: row.team, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_ordinal(row.rank),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: c, height: 1.1)),
            Text(row.team, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(tr('{pts} pts · GD {gd}', {'pts': row.points, 'gd': row.goalDiff}),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

/// The league table with crests, the match's teams picked out in their side's
/// colour. [nearby] keeps the two teams and two places either side. When the
/// teams play in different groups (Argentina's zones) each group is shown.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.match, required this.details, this.nearby = false});
  final Match match;
  final MatchDetails details;
  final bool nearby;

  @override
  Widget build(BuildContext context) {
    final groups = details.tableGroups;
    if (groups.length < 2) return _group(context, details.table);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, g) in groups.indexed) ...[
        if (i > 0) const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(g.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
        ),
        _group(context, g.rows),
      ],
    ]);
  }

  Widget _group(BuildContext context, List<TableRow> table) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    var rows = table;
    final idx = [for (final (i, r) in table.indexed) if (_sideOf(r, match, details) != null) i];
    if (nearby && idx.isNotEmpty) {
      final lo = (idx.reduce(math.min) - 2).clamp(0, table.length - 1);
      final hi = (idx.reduce(math.max) + 2).clamp(0, table.length - 1);
      rows = table.sublist(lo, hi + 1);
    }
    // Leagues without points (basketball, baseball) rank by wins.
    final points = table.any((r) => r.points.isNotEmpty);
    final cols = points
        ? [('P', 24.0), ('W', 24.0), ('D', 24.0), ('L', 24.0), ('GD', 34.0), ('PTS', 36.0)]
        : [('W', 30.0), ('L', 30.0), ('PCT', 44.0), ('GB', 36.0)];
    List<String> values(TableRow r) => points
        ? [r.played, r.won, r.drawn, r.lost, r.goalDiff, r.points]
        : [r.won, r.lost, r.winPct, r.gamesBehind];

    final head = theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700);
    Widget cell(String t, double w, TextStyle? style) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, maxLines: 1, style: style));

    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(children: [
            SizedBox(width: 28, child: Text('#', textAlign: TextAlign.center, style: head)),
            const SizedBox(width: 34),
            Expanded(child: Text(tr('TEAM'), style: head)),
            for (final (h, w) in cols) cell(trTableHead(h), w, head),
          ]),
        ),
        for (final (i, r) in rows.indexed)
          () {
            final side = _sideOf(r, match, details);
            final c = side == 'home' ? cs.primary : cs.tertiary;
            final hi = side != null;
            final gd = int.tryParse(r.goalDiff.replaceAll('+', ''));
            final v = values(r);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hi
                    ? c.withValues(alpha: 0.18)
                    : i.isOdd
                        ? cs.surfaceContainer
                        : null,
                border: Border(left: BorderSide(color: hi ? c : Colors.transparent, width: 4)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: Center(
                    child: hi
                        ? Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                            child: Text('${r.rank}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: side == 'home' ? cs.onPrimary : cs.onTertiary)),
                          )
                        : Text('${r.rank}',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                  ),
                ),
                const SizedBox(width: 8),
                TeamLogo(url: r.logo, name: r.team, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.team,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: hi ? FontWeight.w800 : FontWeight.w500)),
                ),
                for (final (j, (h, w)) in cols.indexed)
                  cell(
                    v[j],
                    w,
                    h == 'PTS'
                        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                        : h == 'GD'
                            ? theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: gd == null || gd == 0
                                    ? null
                                    : gd > 0
                                        ? BankColors.win(context)
                                        : BankColors.loss(context))
                            : theme.textTheme.bodySmall,
                  ),
              ]),
            );
          }(),
      ]),
    );
  }
}
