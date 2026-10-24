import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'format.dart';

/// Screen 2: charts of the bankroll and bet results.
class ChartsScreen extends StatelessWidget {
  const ChartsScreen({super.key, required this.store});
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(store.settings);
    final bets = store.bets;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      _Panel(
        title: tr('Bankroll over time'),
        subtitle: tr("Balance after each day's settled bets, deposits and withdrawals. Dashed line is where you started."),
        child: _BankrollLine(points: bankrollSeries(store.settings, bets, store.txs), start: store.settings.startBankroll, fmt: fmt),
      ),
      _Panel(title: tr('Profit by month'), child: _MonthBars(data: profitByMonth(bets), fmt: fmt)),
      _Panel(title: tr('Results'), child: _ResultsPie(bets: bets)),
      _Panel(
        title: tr('Profit by sport'),
        subtitle: tr('Settled bets only, with ROI and number of bets.'),
        child: _SportBars(data: profitBySport(bets), fmt: fmt),
      ),
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Center(child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
      );
}

/// Y-axis label; skips the chart's raw min and max so they don't collide
/// with the nearest grid label.
Widget _yLabel(BuildContext context, double v, TitleMeta meta, Fmt fmt) {
  if ((v == meta.max || v == meta.min) && v % meta.appliedInterval != 0) return const SizedBox.shrink();
  return SideTitleWidget(meta: meta, child: Text(fmt.compact(v), style: _axis(context)));
}

TextStyle _axis(BuildContext c) =>
    TextStyle(fontSize: 10, color: Theme.of(c).colorScheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]);

class _BankrollLine extends StatelessWidget {
  const _BankrollLine({required this.points, required this.start, required this.fmt});
  final List<DatePoint> points;
  final double start;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return _Empty(tr('Settle a bet or add a deposit to start the line.'));
    final accent = Theme.of(context).colorScheme.primary;
    final t0 = points.first.date;
    double day(DateTime d) => d.difference(t0).inHours / 24;
    final spots = [for (final p in points) FlSpot(day(p.date), p.value)];
    final lo = points.map((p) => p.value).reduce(math.min), hi = points.map((p) => p.value).reduce(math.max);
    final pad = math.max((hi - lo) * 0.1, 1.0);
    final span = spots.last.x - spots.first.x;
    return SizedBox(
      height: 220,
      child: LineChart(LineChartData(
        minY: lo - pad,
        maxY: hi + pad,
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).dividerColor, strokeWidth: 0.6)),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: start, color: Theme.of(context).colorScheme.outline, strokeWidth: 1, dashArray: [4, 4]),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => _yLabel(context, v, meta, fmt),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: span <= 0 ? 1 : span / 3,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(DateFormat.MMMd().format(t0.add(Duration(hours: (v * 24).round()))), style: _axis(context)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${DateFormat.yMMMd().format(t0.add(Duration(hours: (s.x * 24).round())))}\n${fmt.money(s.y)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: accent,
            barWidth: 2.5,
            isCurved: false,
            dotData: FlDotData(show: spots.length <= 20),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent.withValues(alpha: 0.25), accent.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.data, required this.fmt});
  final List<(String, double)> data;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _Empty(tr('No settled bets yet.'));
    final maxAbs = data.map((d) => d.$2.abs()).fold<double>(1, math.max);
    final minVal = data.map((d) => d.$2).fold<double>(0, math.min);
    String label(int i) => DateFormat.MMM().format(DateTime.parse('${data[i].$1}-15'));
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        maxY: maxAbs * 1.15,
        minY: minVal < 0 ? minVal - maxAbs * 0.15 : 0,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).dividerColor, strokeWidth: 0.6)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => _yLabel(context, v, meta, fmt),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(label(v.toInt()), style: _axis(context))),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
              '${label(g.x)}\n${fmt.money(rod.toY, sign: true)}',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].$2,
                width: math.min(22, 200 / data.length),
                color: data[i].$2 >= 0 ? BankColors.win(context) : BankColors.loss(context),
                borderRadius: BorderRadius.circular(3),
              ),
            ]),
        ],
      )),
    );
  }
}

class _ResultsPie extends StatelessWidget {
  const _ResultsPie({required this.bets});
  final List<Bet> bets;

  @override
  Widget build(BuildContext context) {
    if (bets.isEmpty) return _Empty(tr('No bets logged yet.'));
    int n(bool Function(Bet) f) => bets.where(f).length;
    final parts = [
      (tr('Won'), n((b) => b.status == BetStatus.won), BankColors.win(context)),
      (tr('Lost'), n((b) => b.status == BetStatus.lost), BankColors.loss(context)),
      (tr('Pending'), n((b) => b.status == BetStatus.pending), BankColors.pending(context)),
      (
        tr('Push, void, cash-out'),
        n((b) => [BetStatus.push, BetStatus.voided, BetStatus.cashout].contains(b.status)),
        BankColors.neutral(context)
      ),
    ];
    return Row(children: [
      SizedBox(
        width: 140,
        height: 140,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            centerSpaceRadius: 44,
            sectionsSpace: 2,
            sections: [
              for (final p in parts.where((p) => p.$2 > 0))
                PieChartSectionData(value: p.$2.toDouble(), color: p.$3, radius: 22, showTitle: false),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${bets.length}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(tr('bets'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
      ),
      const SizedBox(width: 20),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(child: Text(p.$1)),
                Text('${p.$2}'),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _SportBars extends StatelessWidget {
  const _SportBars({required this.data, required this.fmt});
  final List<GroupStat> data;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _Empty(tr('No settled bets yet.'));
    final maxAbs = data.map((d) => d.profit.abs()).fold<double>(1, math.max);
    final theme = Theme.of(context);
    return Column(children: [
      for (final g in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${sportLabel(g.label)} (${g.count})', style: theme.textTheme.bodyMedium)),
              Text('${fmt.money(g.profit, sign: true)} · ROI ${fmt.pct(g.roi)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: BankColors.forValue(context, g.profit))),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: g.profit.abs() / maxAbs,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: g.profit >= 0 ? BankColors.win(context) : BankColors.loss(context),
              ),
            ),
          ]),
        ),
    ]);
  }
}
