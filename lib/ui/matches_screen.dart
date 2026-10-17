import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'match_page.dart';
import 'parlay_screens.dart';

/// Matches tab: football fixtures for a country on a chosen day.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.store, required this.api, this.today, this.onPick});
  final BankStore store;
  final FixturesApi api;

  /// Set when picking a selection for a parlay: tapping a price returns it
  /// here instead of offering to log it.
  final void Function(Match match, String selection, double odds)? onPick;

  /// Overrides "today" in tests.
  final DateTime? today;

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
    final now = widget.today ?? DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _day = _today;
    _init();
  }

  Future<void> _init() async {
    final saved = countryByCode(await widget.store.pref('matches.country'));
    if (!mounted) return;
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    setState(() => _country = saved ?? defaultCountry(region));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDay());
    await _load();
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
      final list = await widget.api.matches(country, _day, refresh: refresh);
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
      builder: (_) => _CountryPicker(selected: _country),
    );
    if (c == null || !mounted) return;
    setState(() => _country = c);
    widget.store.setPref('matches.country', c.code);
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
            builder: (_) => MatchPage(match: m, store: widget.store, api: widget.api, onPick: widget.onPick)),
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
                        Text(_country?.name ?? 'Country', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Icon(Icons.expand_more, size: 18),
                      ],
                    ),
                    onPressed: _pickCountry,
                  ),
                ),
              ),
              IconButton(tooltip: 'Pick a date', icon: const Icon(Icons.calendar_month_outlined), onPressed: _pickDate),
              IconButton(
                tooltip: 'Refresh',
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
                          isToday ? 'Today' : DateFormat.E().format(d),
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
        action: FilledButton.tonal(onPressed: () => _load(refresh: true), child: const Text('Try again')),
      );
    }
    final list = _matches;
    if (list == null) return ListView();
    if (list.isEmpty) {
      return message(
        Icons.sports_soccer,
        'No matches for ${_country?.name} on ${DateFormat.MMMEd().format(_day)}. Try another day or country.',
      );
    }

    // Group by league, leagues in the country's order.
    final order = {for (final (i, l) in (_country?.leagues ?? const <League>[]).indexed) l.slug: i};
    final groups = <String, List<Match>>{};
    for (final m in list) {
      groups.putIfAbsent(m.league.slug, () => []).add(m);
    }
    final slugs = groups.keys.toList()..sort((a, b) => (order[a] ?? 99).compareTo(order[b] ?? 99));
    final live = list.where((m) => m.state == MatchState.live).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('${list.length} matches${live > 0 ? ' · $live live' : ''}', style: theme.textTheme.bodySmall),
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
  const _MatchCard({required this.match, required this.oddsFormat, required this.onTap, required this.onPick});
  final Match match;
  final OddsFormat oddsFormat;
  final VoidCallback onTap;
  final void Function(String selection, double odds) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = match;
    final live = m.state == MatchState.live;
    final status = switch (m.state) {
      MatchState.scheduled => DateFormat.Hm().format(m.kickoff.toLocal()),
      MatchState.live => m.detail,
      MatchState.finished => 'FT',
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
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
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
                              'LIVE',
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
            ],
          ),
        ),
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
  const _CountryPicker({required this.selected});
  final Country? selected;
  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = countries.where((c) => c.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search country', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                  title: Text(c.name),
                  subtitle: Text(
                    c.leagues.map((l) => l.name).join(' · '),
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
