import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'match_page.dart';
import 'parlay_screens.dart';

/// Matches page: fixtures by country and day, everything live now, and the
/// matches the user starred. The sport switch applies to the first two.
class MatchesTabs extends StatefulWidget {
  const MatchesTabs({super.key, required this.store, required this.api, this.today, this.onPick});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;
  final void Function(Match match, String selection, double odds)? onPick;

  @override
  State<MatchesTabs> createState() => _MatchesTabsState();
}

class _MatchesTabsState extends State<MatchesTabs> {
  Sport? _sport;

  @override
  void initState() {
    super.initState();
    widget.store.pref('matches.sport').then((v) {
      if (mounted) setState(() => _sport = Sport.byName(v));
    });
  }

  void _setSport(Sport s) {
    setState(() => _sport = s);
    widget.store.setPref('matches.sport', s.name);
  }

  @override
  Widget build(BuildContext context) {
    final sport = _sport;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<Sport>(
                key: const Key('sport-switch'),
                showSelectedIcon: false,
                segments: [
                  for (final s in Sport.values)
                    ButtonSegment(
                      value: s,
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text('${s.emoji} ${s.title}')),
                    ),
                ],
                selected: {sport ?? Sport.soccer},
                onSelectionChanged: (v) => _setSport(v.first),
              ),
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: tr('Matches')),
              Tab(text: tr('Live')),
              Tab(text: tr('Favorites')),
            ],
          ),
          Expanded(
            child: sport == null
                ? const SizedBox()
                : TabBarView(
                    children: [
                      MatchesScreen(
                        store: widget.store,
                        api: widget.api,
                        today: widget.today,
                        sport: sport,
                        onPick: widget.onPick,
                      ),
                      LiveMatches(store: widget.store, api: widget.api, sport: sport, onPick: widget.onPick),
                      FavoriteMatches(store: widget.store, api: widget.api, onPick: widget.onPick),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

IconData sportIcon(Sport s) => switch (s) {
  Sport.soccer => Icons.sports_soccer_outlined,
  Sport.basketball => Icons.sports_basketball_outlined,
  Sport.baseball => Icons.sports_baseball_outlined,
};

/// Every live match, A to Z, refreshed every minute while it is on screen.
class LiveMatches extends StatefulWidget {
  const LiveMatches({super.key, required this.store, required this.api, this.sport = Sport.soccer, this.onPick});
  final BankStore store;
  final FixturesApi api;
  final Sport sport;
  final void Function(Match match, String selection, double odds)? onPick;

  @override
  State<LiveMatches> createState() => _LiveMatchesState();
}

class _LiveMatchesState extends State<LiveMatches> {
  List<Match>? _matches;
  String? _error;
  DateTime? _updated;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh while on screen; a hidden bottom tab has tickers off.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _load(refresh: true);
    });
  }

  @override
  void didUpdateWidget(LiveMatches old) {
    super.didUpdateWidget(old);
    if (old.sport != widget.sport) {
      setState(() {
        _matches = null;
        _error = null;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false, bool full = false}) async {
    final sport = widget.sport;
    try {
      final list = await widget.api.liveMatches(sport: sport, refresh: refresh, full: full);
      if (mounted && sport == widget.sport) {
        setState(() {
          _matches = list;
          _error = null;
          _updated = DateTime.now();
        });
      }
    } on FixturesException catch (e) {
      if (mounted && sport == widget.sport) setState(() => _error = e.message);
    }
  }

  void _openMatch(Match m) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MatchPage(match: m, store: widget.store, api: widget.api, onPick: widget.onPick),
    ),
  );

  void _pick(Match m, String selection, double odds) => widget.onPick != null
      ? widget.onPick!(m, selection, odds)
      : pickSelection(context, store: widget.store, api: widget.api, match: m, selection: selection, odds: odds);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _matches;
    final what = switch (widget.sport) {
      Sport.soccer => tr('No live matches right now. Pull down to refresh.'),
      Sport.basketball => tr('No basketball games live right now. Pull down to refresh.'),
      Sport.baseball => tr('No baseball games live right now. Pull down to refresh.'),
    };
    Widget message(IconData icon, String text) => ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ],
    );
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true, full: true),
      child: list == null
          ? (_error != null ? message(Icons.cloud_off, _error!) : const Center(child: CircularProgressIndicator()))
          : list.isEmpty
          ? message(sportIcon(widget.sport), what)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  tr('{n} live now · updated {time}', {'n': list.length, 'time': DateFormat.Hm().format(_updated!)}),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                for (final g in groupByLeague(list)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Row(
                      children: [
                        Flexible(
                          flex: 5,
                          child: Text(
                            g.title.toUpperCase(),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Divider(color: cs.outlineVariant)),
                      ],
                    ),
                  ),
                  for (final m in g.matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MatchCard(
                        match: m,
                        store: widget.store,
                        oddsFormat: widget.store.settings.oddsFormat,
                        onTap: () => _openMatch(m),
                        onPick: (sel, odds) => _pick(m, sel, odds),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

/// Live matches grouped by country and league: countries A to Z
/// (International first), leagues in the country's order, matches A to Z.
List<({String title, List<Match> matches})> groupByLeague(List<Match> list) {
  final groups = <String, List<Match>>{};
  for (final m in list) {
    groups.putIfAbsent(m.league.slug, () => []).add(m);
  }
  int leagueIndex(Country? c, String slug) => c?.leagues.indexWhere((l) => l.slug == slug) ?? 0;
  final slugs = groups.keys.toList()
    ..sort((a, b) {
      final ca = countryOfLeague(a), cb = countryOfLeague(b);
      String key(Country? c) => c == null ? '~' : (c.code == 'int' ? ' ' : c.name);
      final byCountry = key(ca).compareTo(key(cb));
      return byCountry != 0 ? byCountry : leagueIndex(ca, a).compareTo(leagueIndex(cb, b));
    });
  return [
    for (final slug in slugs)
      (
        title: () {
          final c = countryOfLeague(slug), name = groups[slug]!.first.league.name;
          return c == null || c.code == 'int' ? name : '${c.name} · $name';
        }(),
        matches: groups[slug]!..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
      ),
  ];
}

/// Fixtures for a country on a chosen day.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.store,
    required this.api,
    this.today,
    this.sport = Sport.soccer,
    this.onPick,
  });
  final BankStore store;
  final FixturesApi api;
  final Sport sport;

  /// Set when picking a selection for a parlay: tapping a price returns it
  /// here instead of offering to log it.
  final void Function(Match match, String selection, double odds)? onPick;

  /// Overrides "today" in tests.
  final DateTime? today;

  /// Overrides "today" in tests for match lists opened without [today]
  /// (picking a bet or a parlay leg from the bet form).
  @visibleForTesting
  static DateTime? debugToday;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  static const _span = 7; // days shown either side of today in the strip
  late DateTime _today;
  late DateTime _day;
  Country? _country;
  List<Match>? _matches;
  String? _error;
  bool _loading = false;
  int _request = 0;
  final _strip = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = widget.today ?? MatchesScreen.debugToday ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _day = _today;
    _init();
  }

  /// Football keeps the key it always had, so the country picked before
  /// sports came along is kept.
  String get _countryPref => widget.sport == Sport.soccer ? 'matches.country' : 'matches.country.${widget.sport.name}';

  /// The country last picked for this sport, else the phone's own when it
  /// plays it, else the United States (every sport) or the first that does.
  Future<Country> _startCountry() async {
    final sport = widget.sport;
    final saved = countryByCode(await widget.store.pref(_countryPref));
    if (saved != null && saved.has(sport)) return saved;
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    final home = defaultCountry(region);
    if (home.has(sport)) return home;
    final usa = countryByCode('usa');
    return usa != null && usa.has(sport) ? usa : countries.firstWhere((c) => c.has(sport));
  }

  Future<void> _init() async {
    final sport = widget.sport;
    final c = await _startCountry();
    if (!mounted || sport != widget.sport) return;
    setState(() => _country = c);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDay());
    await _load();
  }

  @override
  void didUpdateWidget(MatchesScreen old) {
    super.didUpdateWidget(old);
    if (old.sport != widget.sport) {
      setState(() {
        _matches = null;
        _error = null;
      });
      _request++;
      _init();
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final country = _country;
    if (country == null) return;
    final req = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (!refresh) _matches = null;
    });
    try {
      final list = await widget.api.matches(country, _day, sport: widget.sport, refresh: refresh);
      if (mounted && req == _request) setState(() => _matches = list);
    } catch (e) {
      if (mounted && req == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && req == _request) setState(() => _loading = false);
    }
  }

  void _setDay(DateTime d) {
    setState(() => _day = DateTime(d.year, d.month, d.day));
    _scrollToDay();
    _load();
  }

  void _scrollToDay() {
    if (!_strip.hasClients) return;
    final i = _day.difference(_today).inDays + _span;
    if (i < 0 || i > _span * 2) return;
    _strip.animateTo(
      (i * 60.0 - 120).clamp(0, _strip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickCountry() async {
    final c = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CountryPicker(selected: _country, sport: widget.sport),
    );
    if (c == null || !mounted) return;
    setState(() => _country = c);
    widget.store.setPref(_countryPref, c.code);
    _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: _today.add(const Duration(days: 365)),
    );
    if (d != null) _setDay(d);
  }

  void _openMatch(Match m) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MatchPage(match: m, store: widget.store, api: widget.api, onPick: widget.onPick),
    ),
  );

  /// Tapping a price logs it as a bet or adds it to a parlay.
  void _pick(Match m, String selection, double odds) => widget.onPick != null
      ? widget.onPick!(m, selection, odds)
      : pickSelection(context, store: widget.store, api: widget.api, match: m, selection: selection, odds: odds);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: Text(_country?.flag ?? '🌍', style: const TextStyle(fontSize: 18)),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_country?.name ?? tr('Country'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                    onPressed: _pickCountry,
                  ),
                ),
              ),
              IconButton(tooltip: tr('Pick a date'), icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickDate),
              IconButton(
                tooltip: tr('Refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : () => _load(refresh: true),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.builder(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _span * 2 + 1,
            itemBuilder: (_, i) {
              final d = _today.add(Duration(days: i - _span));
              final sel = d == _day;
              final isToday = d == _today;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _setDay(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    decoration: BoxDecoration(
                      color: sel ? cs.primary : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isToday ? tr('Today') : DateFormat.E().format(d),
                          style: theme.textTheme.labelSmall?.copyWith(color: sel ? cs.onPrimary : cs.onSurfaceVariant),
                        ),
                        Text(
                          '${d.day}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: sel ? cs.onPrimary : cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_day.difference(_today).inDays.abs() > _span)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(DateFormat.yMMMMEEEEd().format(_day), style: theme.textTheme.labelLarge),
          ),
        const SizedBox(height: 4),
        if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(
          child: RefreshIndicator(onRefresh: () => _load(refresh: true), child: _body(theme)),
        ),
      ],
    );
  }

  Widget _body(ThemeData theme) {
    Widget message(IconData icon, String text, {Widget? action}) => ListView(
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ),
        if (action != null) ...[const SizedBox(height: 12), Center(child: action)],
      ],
    );

    if (_error != null) {
      return message(
        Icons.wifi_off,
        _error!,
        action: FilledButton.tonal(onPressed: () => _load(refresh: true), child: Text(tr('Try again'))),
      );
    }
    final list = _matches;
    if (list == null) return ListView();
    if (list.isEmpty) {
      return message(
        sportIcon(widget.sport),
        () {
          final args = {'country': _country?.name, 'day': DateFormat.MMMEd().format(_day)};
          return switch (widget.sport) {
            Sport.soccer => tr('No matches for {country} on {day}. Try another day or country.', args),
            Sport.basketball => tr('No basketball games for {country} on {day}. Try another day or country.', args),
            Sport.baseball => tr('No baseball games for {country} on {day}. Try another day or country.', args),
          };
        }(),
      );
    }

    // Group by league, leagues in the country's order.
    final order = {for (final (i, l) in (_country?.leaguesIn(widget.sport) ?? const <League>[]).indexed) l.slug: i};
    final groups = <String, List<Match>>{};
    for (final m in list) {
      groups.putIfAbsent(m.league.slug, () => []).add(m);
    }
    final slugs = groups.keys.toList()..sort((a, b) => (order[a] ?? 99).compareTo(order[b] ?? 99));
    final live = list.where((m) => m.state == MatchState.live).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
            [trn(list.length, '{n} match', '{n} matches'), if (live > 0) tr('{n} live', {'n': live})].join(' · '),
            style: theme.textTheme.bodySmall),
        for (final slug in slugs) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Row(
              children: [
                Text(
                  groups[slug]!.first.league.name.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
              ],
            ),
          ),
          for (final m in groups[slug]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MatchCard(
                match: m,
                store: widget.store,
                oddsFormat: widget.store.settings.oddsFormat,
                onTap: () => _openMatch(m),
                onPick: (sel, odds) => _pick(m, sel, odds),
              ),
            ),
        ],
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.store,
    required this.oddsFormat,
    required this.onTap,
    required this.onPick,
    this.showDate = false,
  });
  final Match match;
  final BankStore store;
  final OddsFormat oddsFormat;

  /// Show the kick-off day as well as the time (lists across several days).
  final bool showDate;
  final VoidCallback onTap;
  final void Function(String selection, double odds) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    final live = m.state == MatchState.live;
    final status = switch (m.state) {
      MatchState.scheduled =>
        showDate
            ? '${DateFormat.MMMd().format(m.kickoff.toLocal())}\n${DateFormat.Hm().format(m.kickoff.toLocal())}'
            : DateFormat.Hm().format(m.kickoff.toLocal()),
      MatchState.live => m.detail,
      MatchState.finished =>
        showDate ? '${DateFormat.MMMd().format(m.kickoff.toLocal())}\n${m.detail.isEmpty ? tr('FT') : m.detail}' : tr('FT'),
      MatchState.other => m.detail,
    };
    final homeWon =
        m.state == MatchState.finished &&
        (int.tryParse(m.home.score ?? '') ?? 0) > (int.tryParse(m.away.score ?? '') ?? 0);
    final awayWon =
        m.state == MatchState.finished &&
        (int.tryParse(m.away.score ?? '') ?? 0) > (int.tryParse(m.home.score ?? '') ?? 0);

    Widget row(Team t, bool bold) => Row(
      children: [
        TeamLogo(url: t.logo, name: t.name),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
        if (m.hasScore)
          Text(
            t.score ?? '-',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: live ? cs.error : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: live
                    ? Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              tr('LIVE'),
                              style: TextStyle(color: cs.onError, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(status, style: theme.textTheme.labelSmall?.copyWith(color: cs.error)),
                        ],
                      )
                    : Text(
                        status,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: m.state == MatchState.scheduled ? cs.onSurface : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              Container(width: 1, height: 44, margin: const EdgeInsets.only(right: 12), color: cs.outlineVariant),
              Expanded(
                child: Column(
                  children: [
                    row(m.home, homeWon),
                    const SizedBox(height: 8),
                    row(m.away, awayWon),
                    if (m.odds != null && m.state != MatchState.finished) ...[
                      const SizedBox(height: 10),
                      OddsRow(
                        odds: m.odds!,
                        homeName: m.home.name,
                        awayName: m.away.name,
                        format: oddsFormat,
                        onPick: onPick,
                      ),
                    ],
                  ],
                ),
              ),
              FavoriteStar(store: store, match: m, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Star that adds a match to Favorites or takes it off.
class FavoriteStar extends StatelessWidget {
  const FavoriteStar({super.key, required this.store, required this.match, this.compact = false});
  final BankStore store;
  final Match match;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final on = store.isFavorite(match.id);
      final cs = Theme.of(context).colorScheme;
      return IconButton(
        tooltip: on ? tr('Remove from favorites') : tr('Add to favorites'),
        visualDensity: compact ? VisualDensity.compact : null,
        icon: Icon(
          on ? Icons.star_rounded : Icons.star_outline_rounded,
          color: on ? Colors.amber.shade600 : (compact ? cs.onSurfaceVariant : null),
        ),
        onPressed: () async {
          final starred = await store.toggleFavorite(match);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(starred ? tr('Added to favorites') : tr('Removed from favorites')),
                duration: const Duration(seconds: 2),
                persist: false,
              ),
            );
        },
      );
    },
  );
}

/// The matches the user starred: live first, then upcoming by kick-off,
/// then finished, newest first. Status and scores refresh every minute.
class FavoriteMatches extends StatefulWidget {
  const FavoriteMatches({super.key, required this.store, required this.api, this.onPick});
  final BankStore store;
  final FixturesApi api;
  final void Function(Match match, String selection, double odds)? onPick;

  @override
  State<FavoriteMatches> createState() => _FavoriteMatchesState();
}

class _FavoriteMatchesState extends State<FavoriteMatches> {
  Map<String, Match> _current = {};
  Set<String> _loadedIds = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_storeChanged);
    _load();
    // Refresh while on screen; a hidden bottom tab has tickers off.
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _load(refresh: true);
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _storeChanged() {
    final ids = {for (final f in widget.store.favorites) f.matchId};
    if (ids.difference(_loadedIds).isNotEmpty) _load();
    if (mounted) setState(() {});
  }

  Future<void> _load({bool refresh = false}) async {
    final saved = [for (final f in widget.store.favorites) f.toMatch()];
    _loadedIds = {for (final m in saved) m.id};
    if (saved.isEmpty) return;
    final current = await widget.api.refreshMatches(saved, refresh: refresh);
    if (mounted) setState(() => _current = {..._current, ...current});
  }

  void _openMatch(Match m) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MatchPage(match: m, store: widget.store, api: widget.api, onPick: widget.onPick),
    ),
  );

  void _pick(Match m, String selection, double odds) => widget.onPick != null
      ? widget.onPick!(m, selection, odds)
      : pickSelection(context, store: widget.store, api: widget.api, match: m, selection: selection, odds: odds);

  Future<void> _removeAll(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Remove all favorites?')),
        content: Text(trn(count, 'The {n} match you starred will be taken off this list.', 'The {n} matches you starred will be taken off this list.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Remove all'))),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.clearFavorites();
    if (mounted) setState(() => _current = {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now().toUtc();
    final all = [
      for (final f in widget.store.favorites)
        _current[f.matchId] ??
            // Not in any feed any more: once it should be over, list it as ended.
            (now.difference(f.kickoff) > const Duration(hours: 3)
                ? f.toMatch().withStatus(MatchState.other, 'Ended', null, null)
                : f.toMatch()),
    ];
    if (all.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.star_outline_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            tr('Tap the star on any match to follow it here.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }
    final live = all.where((m) => m.state == MatchState.live).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final upcoming = all.where((m) => m.state == MatchState.scheduled).toList()
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final done = all.where((m) => m.state == MatchState.finished || m.state == MatchState.other).toList()
      ..sort((a, b) => b.kickoff.compareTo(a.kickoff));

    Widget section(String title, List<Match> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Text(
                '${title.toUpperCase()} · ${list.length}',
                style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ],
          ),
        ),
        for (final m in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(m.league.name, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
                _MatchCard(
                  match: m,
                  store: widget.store,
                  oddsFormat: widget.store.settings.oddsFormat,
                  showDate: true,
                  onTap: () => _openMatch(m),
                  onPick: (sel, odds) => _pick(m, sel, odds),
                ),
              ],
            ),
          ),
      ],
    );

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    trn(all.length, '{n} favorite', '{n} favorites'),
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  key: const Key('remove-all-favorites'),
                  onPressed: () => _removeAll(all.length),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(tr('Remove all')),
                ),
              ],
            ),
          ),
          if (live.isNotEmpty) section(tr('Live now'), live),
          if (upcoming.isNotEmpty) section(tr('Upcoming'), upcoming),
          if (done.isNotEmpty) section(tr('Finished'), done),
        ],
      ),
    );
  }
}

class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.url, required this.name, this.size = 24});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.secondaryContainer,
      child: Text(
        name.isEmpty ? '?' : name.characters.first,
        style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      width: size,
      height: size,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, p) => p == null ? child : SizedBox(width: size, height: size),
    );
  }
}

/// 1 / X / 2 price buttons. Missing prices are left out.
class OddsRow extends StatelessWidget {
  const OddsRow({
    super.key,
    required this.odds,
    required this.homeName,
    required this.awayName,
    required this.format,
    required this.onPick,
    this.large = false,
  });
  final MatchOdds odds;
  final String homeName;
  final String awayName;
  final OddsFormat format;
  final void Function(String selection, double odds) onPick;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final o = odds;
    final picks = [
      if (o.home != null) ('1', '$homeName to win', o.home!),
      if (o.draw != null) ('X', 'Draw', o.draw!),
      if (o.away != null) ('2', '$awayName to win', o.away!),
    ];
    return Row(
      children: [
        for (final (i, p) in picks.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onPick(p.$2, p.$3),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: large ? 12 : 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p.$1, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      // Long prices (e.g. fractional 100/30) shrink rather than overflow.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatOdds(p.$3, format),
                            style: (large ? theme.textTheme.titleSmall : theme.textTheme.labelLarge)?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.selected, required this.sport});
  final Country? selected;
  final Sport sport;
  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _q = '';

  /// Where each sport's list was when a country was last picked, so it
  /// reopens there.
  static final _offsets = <Sport, double>{};
  static const _rowHeight = 72.0;
  late final _all = countries.where((c) => c.has(widget.sport)).toList();
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset:
        _offsets[widget.sport] ??
        // First time: open with the selected country in view.
        (_all.indexWhere((c) => c.code == widget.selected?.code) * _rowHeight - _rowHeight * 2).clamp(0, 1e9),
  );

  double? get _lastOffset => _offsets[widget.sport];
  set _lastOffset(double? v) => v == null ? _offsets.remove(widget.sport) : _offsets[widget.sport] = v;

  @override
  void dispose() {
    if (_q.isEmpty && _scroll.hasClients) _lastOffset = _scroll.offset;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every country is listed; its matches load once it's picked.
    final list = _all.where((c) => c.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(hintText: tr('Search country'), prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                if (_q.isEmpty && _scroll.hasClients) _lastOffset = _scroll.offset;
                setState(() => _q = v);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_scroll.hasClients) return;
                  final to = v.isEmpty ? (_lastOffset ?? 0) : 0.0;
                  _scroll.jumpTo(to.clamp(0, _scroll.position.maxScrollExtent));
                });
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('country-list'),
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                  title: Text(c.name),
                  subtitle: Text(
                    c.leaguesIn(widget.sport).map((l) => l.name).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: c.code == widget.selected?.code ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
