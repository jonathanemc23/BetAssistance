import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../data/models.dart';
import '../logic/markets.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'format.dart';

/// Screen 2: charts of the bankroll and bet results, for a chosen period.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key, required this.store, this.today});
  final BankStore store;

  /// Fixed date for tests; the real date otherwise.
  final DateTime? today;

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  var _period = ChartPeriod.all;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final fmt = Fmt(store.settings);
    final from = periodStart(_period, widget.today ?? DateTime.now());
    final bets = from == null ? store.bets : store.bets.where((b) => b.date.compareTo(from) >= 0).toList();
    final perBet = profitPerBet(bets);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      _PeriodPicker(value: _period, onChanged: (p) => setState(() => _period = p)),
      const SizedBox(height: 12),
      _Kpis(bets: bets, perBet: perBet, settings: store.settings, fmt: fmt),
      const SizedBox(height: 12),
      _Panel(
        title: tr('Bankroll over time'),
        subtitle: tr("Balance after each day's settled bets, deposits and withdrawals. Dashed line is where you started."),
        child: _BankrollLine(
          points: seriesFrom(bankrollSeries(store.settings, store.bets, store.txs), from),
          start: store.settings.startBankroll,
          fmt: fmt,
        ),
      ),
      _Panel(
        title: tr('Profit per bet'),
        subtitle: tr('Running profit after each settled bet, and what each bet won or lost. Tap a bar to see the bet.'),
        child: _PerBetCharts(points: perBet, fmt: fmt, odds: store.settings.oddsFormat),
      ),
      _Panel(title: tr('Profit by month'), child: _MonthBars(data: profitByMonth(bets), fmt: fmt)),
      _Panel(
        title: tr('Profit by sport'),
        subtitle: tr('Settled bets only. Bars grow right for profit and left for loss.'),
        child: _GroupBars(data: profitBySport(bets), label: sportLabel, fmt: fmt),
      ),
      _Panel(
        title: tr('Win rate by odds'),
        subtitle: tr('Your win rate in each odds range against the rate those odds need to break even. Above the mark, you beat the bookmaker.'),
        child: _OddsValue(data: profitBy(bets, (b) => oddsBand(b.odds), order: oddsBands), fmt: fmt),
      ),
      _Panel(
        title: tr('More breakdowns'),
        subtitle: tr('Where your profit comes from, by type of bet, market, bookmaker or day of the week.'),
        child: _Breakdowns(bets: bets, fmt: fmt),
      ),
      _Panel(title: tr('Results'), child: _ResultsPie(bets: bets)),
    ]);
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final ChartPeriod value;
  final ValueChanged<ChartPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<ChartPeriod>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          segments: [
            ButtonSegment(value: ChartPeriod.days30, label: Text(tr('30 days'))),
            ButtonSegment(value: ChartPeriod.days90, label: Text(tr('90 days'))),
            ButtonSegment(value: ChartPeriod.year, label: Text(tr('This year'))),
            ButtonSegment(value: ChartPeriod.all, label: Text(trc('period', 'All'))),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}

/// Six headline numbers for the period.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.bets, required this.perBet, required this.settings, required this.fmt});
  final List<Bet> bets;
  final List<BetPoint> perBet;
  final Settings settings;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    final s = Stats.compute(settings, bets, const []);
    final st = streaks(perBet);
    final (dd, _) = maxDrawdown(perBet);
    final neutral = Theme.of(context).colorScheme.onSurface;
    final tiles = [
      (tr('Profit'), fmt.money(s.profit, sign: true), BankColors.forValue(context, s.profit)),
      ('ROI', fmt.pct(s.roi), BankColors.forValue(context, s.roi)),
      (tr('Win rate'), s.wins + s.losses == 0 ? '–' : '${(s.winRate * 100).toStringAsFixed(0)}%', neutral),
      (tr('Average odds'), s.avgOdds == 0 ? '–' : formatOdds(s.avgOdds, settings.oddsFormat), neutral),
      (
        tr('Current streak'),
        st.current == 0
            ? '–'
            : st.current > 0
                ? trn(st.current, '{n} win', '{n} wins')
                : trn(-st.current, '{n} loss', '{n} losses'),
        st.current > 0 ? BankColors.win(context) : st.current < 0 ? BankColors.loss(context) : neutral,
      ),
      (tr('Max drawdown'), dd == 0 ? '–' : fmt.money(-dd), dd == 0 ? neutral : BankColors.loss(context)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 560 ? 6 : 3;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final t in tiles) SizedBox(width: w, child: _Kpi(label: t.$1, value: t.$2, color: t.$3)),
      ]);
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                  color: color, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ]),
    );
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
    return ResultsDonut(parts: parts, total: bets.length, unit: tr('bets'));
  }
}

/// A ring of results with the total in the middle and a legend of counts
/// beside it: the Results chart, also used by the bet register's Bought
/// section.
class ResultsDonut extends StatelessWidget {
  const ResultsDonut({super.key, required this.parts, required this.total, required this.unit});

  /// Label, count and colour of each slice.
  final List<(String, int, Color)> parts;
  final int total;
  final String unit;

  @override
  Widget build(BuildContext context) {
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
            Text('$total', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(unit, style: Theme.of(context).textTheme.bodySmall),
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

/// One row per group: name and bets, profit and ROI, win rate, and a bar
/// from a centre zero line, right for profit and left for loss.
class _GroupBars extends StatelessWidget {
  const _GroupBars({required this.data, required this.label, required this.fmt});
  final List<GroupStat> data;
  final String Function(String) label;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _Empty(tr('No settled bets yet.'));
    final maxAbs = data.map((d) => d.profit.abs()).fold<double>(0.01, math.max);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget half(GroupStat g, bool right) {
      final show = right ? g.profit > 0 : g.profit < 0;
      return Expanded(
        child: Align(
          alignment: right ? Alignment.centerLeft : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: show ? math.max(g.profit.abs() / maxAbs, 0.02) : 0,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: right ? BankColors.win(context) : BankColors.loss(context),
                borderRadius: BorderRadius.horizontal(
                  left: right ? Radius.zero : const Radius.circular(3),
                  right: right ? const Radius.circular(3) : Radius.zero,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      for (final g in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label(g.label), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${trn(g.count, '{n} bet', '{n} bets')}', style: muted),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(fmt.money(g.profit, sign: true),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: BankColors.forValue(context, g.profit),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 5),
            SizedBox(
              height: 10,
              child: Row(children: [
                half(g, false),
                Container(width: 1, color: theme.colorScheme.outline),
                half(g, true),
              ]),
            ),
            const SizedBox(height: 4),
            Text(
              [
                'ROI ${fmt.pct(g.roi)}',
                if (g.wins + g.losses > 0) tr('{p} won', {'p': '${(g.winRate * 100).toStringAsFixed(0)}%'}),
              ].join(' · '),
              style: muted,
            ),
          ]),
        ),
    ]);
  }
}

/// Running profit line over every settled bet, then a bar for each of the
/// latest bets.
class _PerBetCharts extends StatelessWidget {
  const _PerBetCharts({required this.points, required this.fmt, required this.odds});
  final List<BetPoint> points;
  final Fmt fmt;
  final OddsFormat odds;

  static const maxBars = 40;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return _Empty(tr('No settled bets yet.'));
    final theme = Theme.of(context);
    final grid = FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor, strokeWidth: 0.6));
    final (dd, ddAt) = maxDrawdown(points);
    final spots = [const FlSpot(0, 0), for (var i = 0; i < points.length; i++) FlSpot(i + 1.0, points[i].cumulative)];
    final lo = spots.map((s) => s.y).reduce(math.min), hi = spots.map((s) => s.y).reduce(math.max);
    final pad = math.max((hi - lo) * 0.12, 1.0);
    final last = points.last.cumulative;
    final lineColor = last >= 0 ? BankColors.win(context) : BankColors.loss(context);
    final bars = points.length > maxBars ? points.sublist(points.length - maxBars) : points;
    final first = points.length - bars.length;
    final barMax = bars.map((p) => p.profit.abs()).fold<double>(1, math.max);
    String betText(BetPoint p) {
      final b = p.bet;
      final what = b.isParlay ? '${tr('Parlay')} · ${trn(b.legs.length, '{n} pick', '{n} picks')}' : b.selection;
      return '$what\n${Fmt.date(b.date)} · @${formatOdds(b.odds, odds)}\n${fmt.money(p.profit, sign: true)}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, alignment: WrapAlignment.spaceBetween, children: [
        _Legend(color: lineColor, text: tr('Running profit')),
        if (dd > 0) Text(tr('Max drawdown {x}', {'x': fmt.money(-dd)}), style: theme.textTheme.bodySmall),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: 190,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: spots.last.x,
          minY: lo - pad,
          maxY: hi + pad,
          gridData: grid,
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: 0, color: theme.colorScheme.outline, strokeWidth: 1, dashArray: [4, 4]),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => _yLabel(context, v, meta, fmt)),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Text(tr('Bet number'), style: _axis(context)),
              axisNameSize: 16,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: math.max(1, (spots.last.x / 4).ceilToDouble()),
                getTitlesWidget: (v, meta) => v == 0 || v != v.roundToDouble()
                    ? const SizedBox.shrink()
                    : SideTitleWidget(meta: meta, child: Text('${v.toInt()}', style: _axis(context))),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (ts) => [
                for (final t in ts)
                  LineTooltipItem(
                    t.x == 0
                        ? fmt.money(0)
                        : '#${t.x.toInt()} · ${Fmt.date(points[t.x.toInt() - 1].bet.date)}\n${fmt.money(t.y, sign: true)}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: lineColor,
              barWidth: 2.2,
              isCurved: false,
              dotData: FlDotData(
                show: ddAt >= 0,
                checkToShowDot: (s, _) => s.x == ddAt + 1,
                getDotPainter: (s, _, _, _) => FlDotCirclePainter(radius: 4, color: BankColors.loss(context), strokeWidth: 2, strokeColor: theme.colorScheme.surface),
              ),
              belowBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: BankColors.win(context).withValues(alpha: 0.12),
              ),
              aboveBarData: BarAreaData(
                show: true,
                applyCutOffY: true,
                cutOffY: 0,
                color: BankColors.loss(context).withValues(alpha: 0.12),
              ),
            ),
          ],
        )),
      ),
      const SizedBox(height: 20),
      Text(
        points.length > maxBars ? tr('Result of each bet, latest {n}', {'n': maxBars}) : tr('Result of each bet'),
        style: theme.textTheme.labelLarge,
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 150,
        child: BarChart(BarChartData(
          maxY: barMax * 1.1,
          minY: -barMax * 1.1,
          borderData: FlBorderData(show: false),
          gridData: grid,
          extraLinesData: ExtraLinesData(horizontalLines: [HorizontalLine(y: 0, color: theme.colorScheme.outline, strokeWidth: 1)]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => _yLabel(context, v, meta, fmt)),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 220,
              getTooltipItem: (g, _, _, _) => BarTooltipItem(
                '#${g.x + 1} · ${betText(points[g.x])}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(x: first + i, barRods: [
                BarChartRodData(
                  toY: bars[i].profit == 0 ? barMax * 0.02 : bars[i].profit,
                  width: math.max(3, math.min(14, 240 / bars.length)),
                  color: bars[i].profit > 0
                      ? BankColors.win(context)
                      : bars[i].profit < 0
                          ? BankColors.loss(context)
                          : BankColors.neutral(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ]),
          ],
        )),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Win rate in each odds range against the break-even rate of its odds.
class _OddsValue extends StatelessWidget {
  const _OddsValue({required this.data, required this.fmt});
  final List<GroupStat> data;
  final Fmt fmt;

  @override
  Widget build(BuildContext context) {
    final rows = data.where((g) => g.wins + g.losses > 0).toList();
    if (rows.isEmpty) return _Empty(tr('No won or lost bets yet.'));
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String pc(double v) => '${(v * 100).toStringAsFixed(0)}%';
    return Column(children: [
      for (final g in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: g.label,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                    TextSpan(text: '  ${trn(g.wins + g.losses, '{n} bet', '{n} bets')}', style: muted),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(fmt.money(g.profit, sign: true),
                  style: theme.textTheme.bodyMedium?.copyWith(color: BankColors.forValue(context, g.profit), fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 5),
            LayoutBuilder(builder: (context, c) {
              final good = g.winRate >= g.breakEven;
              return SizedBox(
                height: 14,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    top: 2,
                    bottom: 2,
                    child: Container(decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(3))),
                  ),
                  Positioned(
                    left: 0,
                    top: 2,
                    bottom: 2,
                    width: c.maxWidth * g.winRate.clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (good ? BankColors.win(context) : BankColors.loss(context)).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth * g.breakEven.clamp(0, 1) - 1).clamp(0, c.maxWidth - 2),
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: ColoredBox(color: theme.colorScheme.onSurface),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 4),
            Text(tr('Won {p} · needs {b} to break even', {'p': pc(g.winRate), 'b': pc(g.breakEven)}), style: muted),
          ]),
        ),
    ]);
  }
}

/// One of several groupings, picked with chips.
class _Breakdowns extends StatefulWidget {
  const _Breakdowns({required this.bets, required this.fmt});
  final List<Bet> bets;
  final Fmt fmt;

  @override
  State<_Breakdowns> createState() => _BreakdownsState();
}

enum _By { type, market, book, weekday }

class _BreakdownsState extends State<_Breakdowns> {
  var _by = _By.type;

  static String _market(Bet b) => b.isParlay ? 'parlay' : (b.market.isNotEmpty ? b.market : marketOf(b.selection));

  @override
  Widget build(BuildContext context) {
    final bets = widget.bets;
    final (data, label) = switch (_by) {
      _By.type => (profitBy(bets, (b) => b.type.name), (String k) => BetTypeX.parse(k).label),
      _By.market => (profitBy(bets, _market), (String k) => k == 'parlay' ? tr('Parlay') : marketById(k).name),
      _By.book => (profitBy(bets, (b) => b.book.trim()), (String k) => k.isEmpty ? tr('No bookmaker') : k),
      _By.weekday => (
          profitBy(bets, (b) => '${DateTime.parse(b.date).weekday}', order: [for (var d = 1; d <= 7; d++) '$d']),
          (String k) => toBeginningOfSentenceCase(DateFormat.EEEE().format(DateTime(2024, 1, int.parse(k)))),
        ),
    };
    final chips = [
      (_By.type, tr('Bet type')),
      (_By.market, tr('Market')),
      (_By.book, tr('Bookmaker')),
      (_By.weekday, tr('Day of the week')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final c in chips)
          ChoiceChip(
            label: Text(c.$2),
            showCheckmark: false,
            selected: _by == c.$1,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _by = c.$1),
          ),
      ]),
      const SizedBox(height: 12),
      _GroupBars(data: data, label: label, fmt: widget.fmt),
    ]);
  }
}
