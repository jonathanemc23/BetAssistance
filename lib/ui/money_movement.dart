import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/odds_history.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'match_page.dart';

/// Where the money is going on one match, read from how the prices moved.
/// Bookmakers don't publish bet counts or stakes, so this never shows them;
/// a shortening price is the visible trace of money coming in.
class MoneyMovementView extends StatefulWidget {
  const MoneyMovementView({super.key, required this.match, required this.details, required this.store});
  final Match match;
  final MatchDetails details;
  final BankStore store;

  @override
  State<MoneyMovementView> createState() => _MoneyMovementViewState();
}

class _MoneyMovementViewState extends State<MoneyMovementView> {
  List<OddsSnapshot>? _history;

  @override
  void initState() {
    super.initState();
    _record();
  }

  @override
  void didUpdateWidget(MoneyMovementView old) {
    super.didUpdateWidget(old);
    if (old.details != widget.details) _record();
  }

  Future<void> _record() async {
    final h = await widget.store.recordOdds(widget.match.id, trackedOdds(widget.details.odds));
    if (mounted) setState(() => _history = h);
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    if (history == null) return const SizedBox.shrink(); // a local read, done in a moment
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = widget.match;
    final fmt = widget.store.settings.oddsFormat;
    final move = marketMove(m, widget.details.odds, history);
    final withOpening = widget.details.odds.where((o) => o.opening != null).firstOrNull;

    return ListView(
      key: const Key('money-movement'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (move == null)
          _Verdict(
            icon: Icons.hourglass_empty,
            title: 'No movement to show yet',
            text: widget.details.odds.isEmpty
                ? 'No bookmaker prices this match yet.'
                : 'There is no opening line for this match, so the app saves the prices each time you open it. '
                      'Check back later to see which way they moved.',
          )
        else ...[
          _Verdict(
            icon: move.flat ? Icons.horizontal_rule : Icons.trending_up,
            title: move.flat
                ? 'The market has barely moved'
                : 'Money is moving towards ${move.backed?.label ?? 'one side'}',
            text: move.fromOpening
                ? '${move.provider} prices since they opened the market.'
                : 'Prices seen on this phone since ${DateFormat('d MMM, HH:mm').format(move.since!.toLocal())}'
                      '${move.provider.isEmpty ? '' : ' (${move.provider})'}.',
          ),
          const SizedBox(height: 12),
          for (final o in move.outcomes) _OutcomeRow(move: o, format: fmt),
          if (withOpening?.opening case final open? when open.over != null && withOpening!.over != null) ...[
            const SizedBox(height: 4),
            _TotalRow(odds: withOpening, format: fmt),
          ],
        ],
        if (history.length >= 2) ...[
          const SizedBox(height: 20),
          Text('Prices seen on this phone', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Chance of each result, from the price each time the match was opened.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: _HistoryChart(history: history, match: m),
          ),
          const SizedBox(height: 8),
          for (final h in history.reversed.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('d MMM, HH:mm').format(h.at.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    [h.home, h.draw, h.away].map((p) => p == null ? '-' : formatOdds(p, fmt)).join('   '),
                    style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
        ] else if (move != null && move.fromOpening) ...[
          const SizedBox(height: 16),
          Text(
            'The app also saves the prices each time you open this match, to chart how they move from here.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: cs.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

String _pct(double c) => '${(c * 100).round()}%';

class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({required this.move, required this.format});
  final OutcomeMove move;
  final OddsFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = move.shift;
    final up = s >= 0.5, down = s <= -0.5;
    final color = up ? Colors.green.shade600 : (down ? cs.error : cs.onSurfaceVariant);
    final sign = s > 0 ? '+' : (s < 0 ? '−' : '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  move.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(up ? Icons.arrow_upward : (down ? Icons.arrow_downward : Icons.remove), size: 16, color: color),
              const SizedBox(width: 2),
              Text(
                '$sign${s.abs().toStringAsFixed(1)} pts',
                style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Odds ${formatOdds(move.from, format)} to ${formatOdds(move.to, format)}  ·  '
            'chance ${_pct(move.chanceFrom)} to ${_pct(move.chanceTo)}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                LinearProgressIndicator(
                  value: math.max(move.chanceFrom, move.chanceTo),
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: color.withValues(alpha: 0.35),
                ),
                LinearProgressIndicator(
                  value: math.min(move.chanceFrom, move.chanceTo),
                  minHeight: 8,
                  backgroundColor: Colors.transparent,
                  color: cs.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            up
                ? 'Shortened: the market moved towards this result.'
                : down
                ? 'Drifted: the market moved away from this result.'
                : 'About the same as before.',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.odds, required this.format});
  final MatchOdds odds;
  final OddsFormat format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final open = odds.opening!;
    final line = odds.totalLine == null ? '' : ' ${odds.totalLine}';
    String side(String name, double? a, double? b) =>
        a == null || b == null ? '' : '$name$line ${formatOdds(a, format)} to ${formatOdds(b, format)}';
    final a = fairChances([open.over, open.under]), b = fairChances([odds.over, odds.under]);
    final towards = a == null || b == null || (b[0] - a[0]).abs() < 0.01 ? null : (b[0] > a[0] ? 'Over' : 'Under');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total goals', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            [
              side('Over', open.over, odds.over),
              side('Under', open.under, odds.under),
            ].where((s) => s.isNotEmpty).join('\n'),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (towards != null) ...[
            const SizedBox(height: 4),
            Text('The market moved towards $towards.', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.history, required this.match});
  final List<OddsSnapshot> history;
  final Match match;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = [cs.primary, cs.outline, cs.tertiary];
    final names = [match.home.name, 'Draw', match.away.name];
    final series = <List<double?>>[[], [], []];
    for (final h in history) {
      final c = fairChances([h.home, h.draw, h.away]) ?? fairChances([h.home, h.away]);
      final full = c == null ? null : (c.length == 3 ? c : [c[0], null, c[1]]);
      for (var i = 0; i < 3; i++) {
        series[i].add(full?[i]);
      }
    }
    return Column(
      children: [
        Expanded(
          child: CustomPaint(size: Size.infinite, painter: _LinesPainter(series, colors, cs.outlineVariant)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            for (var i = 0; i < 3; i++)
              if (series[i].any((v) => v != null))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(names[i], style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.series, this.colors, this.grid);
  final List<List<double?>> series;
  final List<Color> colors;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, size.height * f), Offset(size.width, size.height * f), g);
    }
    final n = series.first.length;
    for (var s = 0; s < series.length; s++) {
      final p = Paint()
        ..color = colors[s]
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = series[s][i];
        if (v == null) continue;
        final pt = Offset(n == 1 ? size.width / 2 : size.width * i / (n - 1), size.height * (1 - v));
        started ? path.lineTo(pt.dx, pt.dy) : path.moveTo(pt.dx, pt.dy);
        started = true;
        canvas.drawCircle(pt, 3, Paint()..color = colors[s]);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.series != series;
}

/// Bet Tools entry: pick one of the starred matches to see its money movement.
class MoneyToolPage extends StatelessWidget {
  const MoneyToolPage({super.key, required this.store, required this.api, required this.onOpenMatches});
  final BankStore store;
  final FixturesApi api;
  final VoidCallback onOpenMatches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Money movement')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final favs = store.favorites;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'See which way the market is moving on a match. Pick one of your starred matches, or open any match '
                'and go to its Money tab.',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (favs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(Icons.star_outline, size: 40, color: cs.primary),
                      const SizedBox(height: 8),
                      const Text('Star a match to follow its money here.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.pop(context);
                          onOpenMatches();
                        },
                        child: const Text('Browse matches'),
                      ),
                    ],
                  ),
                ),
              for (final f in favs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${f.home} vs ${f.away}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${f.leagueName} · ${DateFormat('EEE d MMM, HH:mm').format(f.kickoff.toLocal())}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MatchPage(match: f.toMatch(), store: store, api: api, initialTab: 1),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
