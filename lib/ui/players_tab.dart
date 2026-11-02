import 'package:flutter/material.dart';

import '../data/fixtures.dart';
import '../l10n/l10n.dart';
import 'format.dart';
import 'matches_screen.dart';

/// A basketball match's box score: every player's stats for one team at a
/// time, starters then bench, with the team's totals. Tapping a column
/// heading sorts by it; tapping a player shows their whole line. While the
/// game is on, the page reads the feed again and this updates in place.
class PlayersTab extends StatefulWidget {
  const PlayersTab({super.key, required this.match, required this.details, this.live = false, this.every});
  final Match match;
  final MatchDetails details;

  /// The game is on and the stats update every [every].
  final bool live;
  final Duration? every;

  @override
  State<PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<PlayersTab> {
  String _side = 'home';

  /// The column the players are sorted by (ESPN's key, such as "points"),
  /// or null for ESPN's order: starters, then the bench.
  String? _sortBy;

  static const _rowHeight = 44.0, _nameWidth = 140.0;

  @override
  Widget build(BuildContext context) {
    final d = widget.details;
    if (d.boxScore.isEmpty) {
      return _empty(
        context,
        d.state == MatchState.scheduled || widget.match.state == MatchState.scheduled
            ? tr('Player stats appear here once the game tips off, and update live during it.')
            : tr('There are no player stats for this game yet.'),
      );
    }
    final box = d.boxScoreOf(_side) ?? d.boxScore.first;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (widget.live) _LiveNote(every: widget.every),
        _TeamSwitch(
          match: widget.match,
          details: d,
          side: box.side,
          onChanged: (s) => setState(() => _side = s),
        ),
        const SizedBox(height: 12),
        _table(context, box),
        const SizedBox(height: 10),
        Text(
          tr('Tap a column to sort, or a player for their full line.'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        ..._didNotPlay(context, box),
      ],
    );
  }

  Widget _table(BuildContext context, TeamBoxScore box) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final played = [for (final p in box.players) if (p.played) p];
    final sortCol = _sortBy == null ? -1 : box.column(_sortBy!);

    // Rows: a heading per group in ESPN's order, or one list when sorted.
    final rows = <_Row>[];
    if (sortCol >= 0) {
      final sorted = [...played]..sort((a, b) => _num(b.at(sortCol)).compareTo(_num(a.at(sortCol))));
      rows.addAll(sorted.map(_Row.player));
    } else {
      final starters = played.where((p) => p.starter).toList();
      final bench = played.where((p) => !p.starter).toList();
      if (starters.isNotEmpty) rows.add(_Row.heading(tr('Starters')));
      rows.addAll(starters.map(_Row.player));
      if (bench.isNotEmpty) rows.add(_Row.heading(tr('Bench')));
      rows.addAll(bench.map(_Row.player));
    }
    final hasTotals = box.totals.any((t) => t.isNotEmpty);

    final pointsCol = box.column('points');
    final order = _order(box);
    // The best figure in each column, to pick out who led the team in it.
    final best = <int, double>{
      for (var i = 0; i < box.labels.length; i++)
        if (_rankable(box.keys.elementAtOrNull(i)) && box.keys[i] != 'minutes')
          i: played.map((p) => _num(p.at(i))).fold<double>(double.negativeInfinity, (a, b) => b > a ? b : a),
    };

    final headStyle = theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant);
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget nameCell(_Row r) {
      final p = r.player;
      if (p == null) {
        return Container(
          height: 28,
          alignment: Alignment.centerLeft,
          child: Text(r.heading!.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: cs.primary, fontWeight: FontWeight.w800)),
        );
      }
      return InkWell(
        onTap: () => _showPlayer(context, box, p),
        child: SizedBox(
          height: _rowHeight,
          child: Row(children: [
            _Headshot(player: p, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.shortName.isNotEmpty ? p.shortName : p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  [if (p.jersey.isNotEmpty) '#${p.jersey}', if (p.position.isNotEmpty) p.position, if (p.ejected) tr('Ejected')].join(' · '),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(color: p.ejected ? BankColors.loss(context) : cs.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
        ),
      );
    }

    // Set from the room there is, so the column at the edge shows half-way.
    var scale = 1.0;
    double width(int i) => scale * _baseWidth(box, i);

    Widget statCell(_Row r, int i) {
      final p = r.player;
      if (p == null) return SizedBox(width: width(i), height: 28);
      final v = p.at(i);
      final top = best.containsKey(i) && best[i]! > 0 && _num(v) == best[i];
      final key = box.keys.elementAtOrNull(i);
      final color = key == 'plusMinus'
          ? (_num(v) > 0 ? BankColors.win(context) : _num(v) < 0 ? BankColors.loss(context) : null)
          : top
              ? cs.primary
              : null;
      return SizedBox(
        width: width(i),
        height: _rowHeight,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v,
                style: cellStyle?.copyWith(
                  color: color,
                  fontWeight: i == pointsCol || top || i == sortCol ? FontWeight.w800 : null,
                )),
          ),
        ),
      );
    }

    Widget head(int i) {
      final key = box.keys.elementAtOrNull(i);
      final sortable = _rankable(key);
      final on = i == sortCol;
      final label = Text(box.labels[i], style: headStyle?.copyWith(color: on ? cs.primary : null));
      final cell = SizedBox(
        width: width(i),
        height: 32,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              label,
              if (on) Icon(Icons.arrow_downward, size: 10, color: cs.primary),
            ]),
          ),
        ),
      );
      final tip = box.descriptions.elementAtOrNull(i);
      final tapped = !sortable
          ? cell
          : InkWell(onTap: () => setState(() => _sortBy = on ? null : key), child: cell);
      return tip == null || tip.isEmpty ? tapped : Tooltip(message: tip, child: tapped);
    }

    Widget divider() => Divider(height: 1, color: cs.outlineVariant);

    final totalsName = SizedBox(
      height: _rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(tr('Team totals'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: _nameWidth,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 32,
              child: Align(alignment: Alignment.centerLeft, child: Text(tr('Player').toUpperCase(), style: headStyle)),
            ),
            divider(),
            for (final r in rows) nameCell(r),
            if (hasTotals) ...[divider(), totalsName],
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            scale = _fitScale(box, order, constraints.maxWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [for (final i in order) head(i)]),
                SizedBox(width: _statsWidth(box, width), child: divider()),
                for (final r in rows) Row(children: [for (final i in order) statCell(r, i)]),
                if (hasTotals) ...[
                  SizedBox(width: _statsWidth(box, width), child: divider()),
                  Row(children: [
                    for (final i in order)
                      SizedBox(
                        width: width(i),
                        height: _rowHeight,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(box.totals.elementAtOrNull(i) ?? '',
                                style: cellStyle?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                  ]),
                ],
              ]),
            );
          }),
        ),
      ]),
    );
  }

  /// Points, rebounds and assists first, then the rest in ESPN's order.
  static List<int> _order(TeamBoxScore box) {
    final first = [for (final k in const ['points', 'rebounds', 'assists']) box.column(k)].where((i) => i >= 0).toList();
    return [...first, for (var i = 0; i < box.labels.length; i++) if (!first.contains(i)) i];
  }

  static double _baseWidth(TeamBoxScore box, int i) => switch (box.keys.elementAtOrNull(i) ?? '') {
        'fieldGoalsMade-fieldGoalsAttempted' ||
        'threePointFieldGoalsMade-threePointFieldGoalsAttempted' ||
        'freeThrowsMade-freeThrowsAttempted' =>
          56,
        'plusMinus' => 44,
        _ => 40,
      };

  /// How much to widen the columns so that, in [room], the last one in view
  /// is cut at its middle: a hint that the table scrolls. 1 when all fit.
  static double _fitScale(TeamBoxScore box, List<int> order, double room) {
    final total = order.fold<double>(0, (a, i) => a + _baseWidth(box, i));
    if (!room.isFinite || room <= 0 || total <= room) return 1;
    var shown = 0.0, scale = 1.0;
    for (final i in order) {
      final w = _baseWidth(box, i);
      if (shown + w / 2 > room) break;
      scale = room / (shown + w / 2);
      shown += w;
    }
    return scale.clamp(1.0, 1.6);
  }

  static double _statsWidth(TeamBoxScore box, double Function(int) width) {
    var w = 0.0;
    for (var i = 0; i < box.labels.length; i++) {
      w += width(i);
    }
    return w;
  }

  List<Widget> _didNotPlay(BuildContext context, TeamBoxScore box) {
    final out = [for (final p in box.players) if (!p.played) p];
    if (out.isEmpty) return const [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return [
      const SizedBox(height: 16),
      Text(tr('Did not play').toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: cs.primary)),
      const SizedBox(height: 6),
      for (final p in out)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            _Headshot(player: p, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (p.reason.isNotEmpty)
              Flexible(
                child: Text(_reason(p.reason),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ]),
        ),
    ];
  }

  void _showPlayer(BuildContext context, TeamBoxScore box, BoxPlayer p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Row(children: [
                _Headshot(player: p, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [box.team, if (p.jersey.isNotEmpty) '#${p.jersey}', if (p.position.isNotEmpty) p.position].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final i in _order(box))
                  if (p.at(i).isNotEmpty)
                    Container(
                      width: 92,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                      child: Column(children: [
                        Text(p.at(i),
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(height: 2),
                        Text(
                          box.descriptions.elementAtOrNull(i)?.isNotEmpty == true ? box.descriptions[i] : box.labels[i],
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ]),
                    ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sports_basketball, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }

  /// "COACH'S DECISION" -> "Coach's decision"
  static String _reason(String r) {
    final s = r.trim().toLowerCase();
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  /// Columns worth sorting by and picking out a leader in.
  static bool _rankable(String? key) => key != null && key != 'fouls' && key != 'turnovers';

  /// "8-13" -> 8, "+5" -> 5, "37" -> 37; anything else sorts last.
  static double _num(String v) {
    final m = RegExp(r'^[+-]?\d+(?:\.\d+)?').firstMatch(v.trim());
    return m == null ? double.negativeInfinity : double.parse(m[0]!.replaceFirst('+', ''));
  }
}

class _Row {
  _Row.player(BoxPlayer this.player) : heading = null;
  _Row.heading(String this.heading) : player = null;
  final BoxPlayer? player;
  final String? heading;
}

class _LiveNote extends StatelessWidget {
  const _LiveNote({this.every});
  final Duration? every;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            every == null
                ? tr('Live stats')
                : tr('Live stats, updated every {seconds} seconds', {'seconds': '${every!.inSeconds}'}),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _TeamSwitch extends StatelessWidget {
  const _TeamSwitch({required this.match, required this.details, required this.side, required this.onChanged});
  final Match match;
  final MatchDetails details;
  final String side;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    ButtonSegment<String> seg(String s, Team t, TeamInfo info) => ButtonSegment(
          value: s,
          icon: TeamLogo(url: t.logo ?? info.logo, name: t.name, size: 20),
          label: Text(t.shortName.isNotEmpty ? t.shortName : t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        if (details.boxScoreOf('home') != null) seg('home', match.home, details.home),
        if (details.boxScoreOf('away') != null) seg('away', match.away, details.away),
      ],
      selected: {side},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _Headshot extends StatelessWidget {
  const _Headshot({required this.player, required this.size});
  final BoxPlayer player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.secondaryContainer,
      child: Text(player.jersey.isNotEmpty ? player.jersey : (player.name.isEmpty ? '?' : player.name.characters.first),
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
    );
    final url = player.headshot;
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: cs.secondaryContainer,
        child: Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}
