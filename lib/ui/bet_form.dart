import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'format.dart';

/// Full-screen form to log a new bet or edit an existing one.
class BetFormPage extends StatefulWidget {
  const BetFormPage({super.key, required this.store, this.bet});
  final BankStore store;
  final Bet? bet;

  @override
  State<BetFormPage> createState() => _BetFormPageState();
}

class _BetFormPageState extends State<BetFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _selection, _event, _stake, _odds, _book, _notes, _cashout;
  late String _sport, _date;
  late BetStatus _status;

  Settings get _settings => widget.store.settings;
  bool get _isNew => widget.bet == null;

  @override
  void initState() {
    super.initState();
    final b = widget.bet;
    final lastSport = widget.store.bets.isEmpty ? 'Soccer' : widget.store.bets.first.sport;
    _selection = TextEditingController(text: b?.selection ?? '');
    _event = TextEditingController(text: b?.event ?? '');
    _stake = TextEditingController(text: b != null ? _num(b.stake) : (_settings.unit > 0 ? _num(_settings.unit) : ''));
    _odds = TextEditingController(text: b != null ? formatOdds(b.odds, _settings.oddsFormat) : '');
    _book = TextEditingController(text: b?.book ?? '');
    _notes = TextEditingController(text: b?.notes ?? '');
    _cashout = TextEditingController(text: b?.cashout != null ? _num(b!.cashout!) : '');
    _sport = b?.sport ?? lastSport;
    if (!sports.contains(_sport)) _sport = 'Other';
    _date = b?.date ?? isoDate(DateTime.now());
    _status = b?.status ?? BetStatus.pending;
    for (final c in [_stake, _odds]) {
      c.addListener(() => setState(() {}));
    }
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [_selection, _event, _stake, _odds, _book, _notes, _cashout]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _stakeVal => double.tryParse(_stake.text.replaceAll(',', '.'));
  double? get _oddsVal => parseOdds(_odds.text, _settings.oddsFormat);

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = isoDate(d));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final bet = Bet(
      id: widget.bet?.id,
      selection: _selection.text.trim(),
      event: _event.text.trim(),
      sport: _sport,
      date: _date,
      stake: _stakeVal!,
      odds: double.parse(_oddsVal!.toStringAsFixed(4)),
      book: _book.text.trim(),
      status: _status,
      cashout: _status == BetStatus.cashout ? double.tryParse(_cashout.text.replaceAll(',', '.')) : null,
      notes: _notes.text.trim(),
      created: widget.bet?.created ?? DateTime.now().toIso8601String(),
    );
    await widget.store.saveBet(bet);
    if (mounted) Navigator.pop(context, _isNew ? 'Bet logged' : 'Bet updated');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this bet?'),
        content: const Text('It will be removed from your totals and charts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.deleteBet(widget.bet!);
    if (mounted) Navigator.pop(context, 'Bet deleted');
  }

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(_settings);
    final american = _settings.oddsFormat == OddsFormat.american;
    final s = _stakeVal, o = _oddsVal;
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Log a bet' : 'Edit bet'),
        actions: [
          if (!_isNew) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _selection,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Selection', hintText: 'e.g. Arsenal to win, Over 2.5 goals'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Add the selection you bet on' : null,
            ),
            gap,
            TextFormField(
              controller: _event,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Event (optional)', hintText: 'e.g. Arsenal vs Chelsea'),
            ),
            gap,
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _sport,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sport'),
                  items: [for (final sp in sports) DropdownMenuItem(value: sp, child: Text(sp))],
                  onChanged: (v) => setState(() => _sport = v ?? _sport),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                    child: Text(Fmt.date(_date)),
                  ),
                ),
              ),
            ]),
            gap,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _stake,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Stake (${_settings.currency})'),
                  validator: (_) => (_stakeVal ?? 0) > 0 ? null : 'Enter a stake above zero',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _odds,
                  keyboardType: TextInputType.numberWithOptions(decimal: true, signed: american),
                  decoration: InputDecoration(labelText: american ? 'Odds (+150 / -110)' : 'Odds (e.g. 2.50)'),
                  validator: (_) => _oddsVal != null ? null : (american ? 'Use +150 or -110' : 'Above 1.00'),
                ),
              ),
            ]),
            if (s != null && s > 0 && o != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Returns ${fmt.money(s * o)} if it wins (profit ${fmt.money(s * (o - 1))}). '
                  'Implied probability ${(100 / o).toStringAsFixed(1)}%.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            gap,
            TextFormField(controller: _book, decoration: const InputDecoration(labelText: 'Bookmaker (optional)')),
            gap,
            Text('Result', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final st in BetStatus.values)
                ChoiceChip(
                  label: Text(st.label),
                  selected: _status == st,
                  onSelected: (_) => setState(() => _status = st),
                ),
            ]),
            if (_status == BetStatus.cashout) ...[
              gap,
              TextFormField(
                controller: _cashout,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Cash-out amount received'),
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) >= 0
                    ? null
                    : 'Enter the amount you received',
              ),
            ],
            gap,
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: Text(_isNew ? 'Log bet' : 'Save changes')),
          ],
        ),
      ),
    );
  }
}
