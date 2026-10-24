import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
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
Future<MarketPick?> showMarketSheet(
  BuildContext context, {
  required String event,
  required OddsFormat format,
  bool askOdds = false,
  String? initialMarket,
}) =>
    showModalBottomSheet<MarketPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketSheet(event: event, format: format, askOdds: askOdds, initialMarket: initialMarket),
    );

class _MarketSheet extends StatefulWidget {
  const _MarketSheet({required this.event, required this.format, required this.askOdds, this.initialMarket});
  final String event;
  final OddsFormat format;
  final bool askOdds;
  final String? initialMarket;

  @override
  State<_MarketSheet> createState() => _MarketSheetState();
}

class _MarketSheetState extends State<_MarketSheet> {
  late Market _market = marketById(widget.initialMarket ?? 'handicap');
  late final (String, String) _teams = teamsOf(widget.event);
  String? _side;
  final _line = TextEditingController();
  final _text = TextEditingController();
  final _odds = TextEditingController();

  @override
  void initState() {
    super.initState();
    _select(_market);
    for (final c in [_line, _text, _odds]) {
      c.addListener(() => setState(() {}));
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
    final sides = m.sides(_teams.$1, _teams.$2);
    _side = sides.isEmpty ? null : sides.first;
    _line.text = m.line == null ? '' : formatLine(m.line!, signed: m.signedLine);
    _text.clear();
  }

  double? get _lineVal => double.tryParse(_line.text.replaceAll(',', '.').replaceAll('+', ''));

  void _stepLine(int dir) {
    final v = (_lineVal ?? _market.line ?? 0) + dir * _market.step;
    _line.text = formatLine(v, signed: _market.signedLine);
  }

  String get _preview => _market.selection(side: _side, line: _market.hasLine ? _lineVal : null, text: _text.text);

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
    final sides = _market.sides(_teams.$1, _teams.$2);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Choose a market'), style: theme.textTheme.titleLarge),
          if (widget.event.isNotEmpty) Text(widget.event, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in markets)
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
                ChoiceChip(label: Text(trPick(s)), selected: s == _side, onSelected: (_) => setState(() => _side = s)),
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
              decoration: InputDecoration(
                labelText: tr('Odds'),
                hintText: widget.format == OddsFormat.american ? '+150' : '1.90',
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
          const SizedBox(height: 14),
          FilledButton(
            onPressed: !_valid
                ? null
                : () => Navigator.pop(
                      context,
                      MarketPick(_market.id, _preview,
                          odds: widget.askOdds ? parseOdds(_odds.text, widget.format) : null),
                    ),
            child: Text(tr('Use this pick')),
          ),
        ]),
      ),
    );
  }
}
