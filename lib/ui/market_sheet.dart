import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/models.dart';
import '../logic/markets.dart';
import '../logic/stats.dart';

/// A pick built in the market sheet.
class MarketPick {
  const MarketPick(this.market, this.selection, {this.odds});
  final String market;
  final String selection;
  final double? odds;
}

/// Sheet to build a pick in any market: choose the market, the side and the
/// line (or type a score or player). With [askOdds] it also asks for the price.
/// For a pick on a listed [match] the markets suit its sport, and the odds
/// are filled in from [books] (the match's own prices by default) when a
/// bookmaker prices that pick; otherwise the user types them.
Future<MarketPick?> showMarketSheet(
  BuildContext context, {
  required String event,
  required OddsFormat format,
  bool askOdds = false,
  String? initialMarket,
  Match? match,
  List<MatchOdds>? books,
  String? action,
  VoidCallback? onDetails,
}) =>
    showModalBottomSheet<MarketPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketSheet(
        event: event,
        format: format,
        askOdds: askOdds,
        initialMarket: initialMarket,
        match: match,
        books: books ?? [?match?.odds],
        action: action,
        onDetails: onDetails,
      ),
    );

/// Every pick [o] prices, by its selection text as the app writes it:
/// "Arsenal to win", "Arsenal or draw", "Over 2.5 goals".
Map<String, double> bookPrices(MatchOdds o, String home, String away, {String unit = 'goals'}) {
  final line = o.totalLine == null ? '' : formatLine(o.totalLine!);
  return {
    if (o.home != null) '$home to win': o.home!,
    if (o.draw != null) 'Draw': o.draw!,
    if (o.away != null) '$away to win': o.away!,
    if (o.over != null && line.isNotEmpty) 'Over $line $unit': o.over!,
    if (o.under != null && line.isNotEmpty) 'Under $line $unit': o.under!,
    for (final (label, price) in o.extras)
      switch (label) {
        'Double chance 1X' => '$home or draw',
        'Double chance 12' => '$home or $away',
        'Double chance X2' => '$away or draw',
        _ => label,
      }: price,
  };
}

/// The best price any of [books] has for [selection], with who offers it.
(double, String)? bestPrice(String selection, List<MatchOdds> books, String home, String away, {String unit = 'goals'}) {
  (double, String)? best;
  for (final o in books) {
    final p = bookPrices(o, home, away, unit: unit)[selection];
    if (p != null && (best == null || p > best.$1)) best = (p, o.provider);
  }
  return best;
}

class _MarketSheet extends StatefulWidget {
  const _MarketSheet({
    required this.event,
    required this.format,
    required this.askOdds,
    this.initialMarket,
    this.match,
    this.books = const [],
    this.action,
    this.onDetails,
  });
  final String event;
  final OddsFormat format;
  final bool askOdds;
  final String? initialMarket;
  final Match? match;
  final List<MatchOdds> books;
  final String? action;
  final VoidCallback? onDetails;

  @override
  State<_MarketSheet> createState() => _MarketSheetState();
}

class _MarketSheetState extends State<_MarketSheet> {
  late final Sport _sport = widget.match?.league.knownSport ?? Sport.soccer;
  late final List<Market> _markets = widget.match == null ? markets : marketsFor(_sport.espn);
  late Market _market = _markets.firstWhere((m) => m.id == (widget.initialMarket ?? (widget.match == null ? 'handicap' : 'result')),
      orElse: () => _markets.first);
  late final (String, String) _teams =
      widget.match == null ? teamsOf(widget.event) : (widget.match!.home.name, widget.match!.away.name);
  String? _side;
  final _line = TextEditingController();
  final _text = TextEditingController();
  final _odds = TextEditingController();

  /// Who the odds in the box came from, while they are a bookmaker's price
  /// the user hasn't changed.
  String? _priceFrom;

  @override
  void initState() {
    super.initState();
    _select(_market);
    for (final c in [_line, _text, _odds]) {
      c.addListener(() => setState(() {}));
    }
    _line.addListener(_fillPrice);
  }

  bool get _draws => _sport == Sport.soccer;

  /// Puts in the bookmaker's price for the pick as it stands, or clears one
  /// put in for an earlier pick.
  void _fillPrice() {
    if (!widget.askOdds || widget.books.isEmpty) return;
    final p = bestPrice(_preview, widget.books, _teams.$1, _teams.$2, unit: _sport.scoreUnit);
    if (p != null) {
      final text = formatOdds(p.$1, widget.format);
      if (_odds.text != text) _odds.text = text;
      _priceFrom = p.$2;
    } else if (_priceFrom != null) {
      _odds.clear();
      _priceFrom = null;
    }
  }

  @override
  void dispose() {
    _line.dispose();
    _text.dispose();
    _odds.dispose();
    super.dispose();
  }

  void _select(Market m) {
    _market = m;
    final sides = m.sides(_teams.$1, _teams.$2, draws: _draws);
    _side = sides.isEmpty ? null : sides.first;
    _line.text = m.line == null ? '' : formatLine(m.line!, signed: m.signedLine);
    _text.clear();
    _fillPrice();
  }

  void _pickSide(String s) {
    _side = s;
    _fillPrice();
  }

  double? get _lineVal => double.tryParse(_line.text.replaceAll(',', '.').replaceAll('+', ''));

  void _stepLine(int dir) {
    final v = (_lineVal ?? _market.line ?? 0) + dir * _market.step;
    _line.text = formatLine(v, signed: _market.signedLine);
  }

  String get _preview =>
      _market.selection(side: _side, line: _market.hasLine ? _lineVal : null, text: _text.text, unit: _sport.scoreUnit);

  bool get _valid {
    if (_market.hasLine && _lineVal == null) return false;
    if (_market.hasText && _text.text.trim().isEmpty) return false;
    if (widget.askOdds && parseOdds(_odds.text, widget.format) == null) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sides = _market.sides(_teams.$1, _teams.$2, draws: _draws);
    final note = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Choose a market'), style: theme.textTheme.titleLarge),
                if (widget.event.isNotEmpty) Text(widget.event, style: theme.textTheme.bodySmall),
              ]),
            ),
            if (widget.onDetails != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDetails!();
                },
                icon: const Icon(Icons.insights, size: 18),
                label: Text(tr('Match details')),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in _markets)
              ChoiceChip(
                label: Text(m.name),
                selected: m.id == _market.id,
                onSelected: (_) => setState(() => _select(m)),
              ),
          ]),
          const SizedBox(height: 16),
          if (sides.isNotEmpty) ...[
            Text(tr('Pick'), style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in sides)
                ChoiceChip(label: Text(_sideLabel(s)), selected: s == _side, onSelected: (_) => setState(() => _pickSide(s))),
            ]),
            const SizedBox(height: 14),
          ],
          if (_market.hasLine) ...[
            Text(_market.id == 'handicap' ? tr('Handicap line') : tr('Line'), style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(children: [
              IconButton.filledTonal(
                  tooltip: tr('Lower line'), onPressed: () => _stepLine(-1), icon: const Icon(Icons.remove)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _line,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: tr('Raise line'), onPressed: () => _stepLine(1), icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 14),
          ],
          if (_market.hasText) ...[
            TextField(
              controller: _text,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(hintText: _market.hint),
            ),
            const SizedBox(height: 14),
          ],
          if (widget.askOdds) ...[
            TextField(
              controller: _odds,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => _priceFrom = null,
              decoration: InputDecoration(
                labelText: tr('Odds'),
                hintText: widget.format == OddsFormat.american ? '+150' : '1.90',
                helperText: _priceFrom != null
                    ? (_priceFrom!.isEmpty ? tr('Bookmaker price') : tr('Price from {book}', {'book': _priceFrom!}))
                    : tr('No price for this pick in the app: type the odds you got.'),
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.check_circle_outline, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_valid || !_market.hasText ? trPick(_preview) : tr('Type your pick'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (widget.match != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(scoreSettled.contains(_market.id) ? Icons.auto_mode : Icons.touch_app_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scoreSettled.contains(_market.id)
                      ? tr('Settles by itself from the final score.')
                      : tr('The final score does not settle this market: you mark the result.'),
                  style: note,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: !_valid
                ? null
                : () => Navigator.pop(
                      context,
                      MarketPick(_market.id, _preview,
                          odds: widget.askOdds ? parseOdds(_odds.text, widget.format) : null),
                    ),
            child: Text(widget.action ?? tr('Use this pick')),
          ),
        ]),
      ),
    );
  }

  /// A side chip's text: "Arsenal over" reads better as "Arsenal: Over".
  String _sideLabel(String s) {
    if (_market.id == 'team_goals') {
      final i = s.lastIndexOf(' ');
      return '${s.substring(0, i)}: ${trPick(s.endsWith('over') ? 'Over' : 'Under')}';
    }
    return trPick(s);
  }
}
