import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/stats.dart';
import 'format.dart';
import 'share_ui.dart';

/// Opens the bet form: [bet] edits an existing bet, [template] pre-fills a
/// new one (from a share link or "log again"). Shows the result as a snackbar.
Future<void> openBetForm(BuildContext context, BankStore store, {Bet? bet, Bet? template}) async {
  final messenger = ScaffoldMessenger.of(context);
  final msg = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => BetFormPage(store: store, bet: bet, template: template)),
  );
  if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
}

class _Leg {
  _Leg([BetLeg? l])
      : selection = TextEditingController(text: l?.selection ?? ''),
        event = TextEditingController(text: l?.event ?? ''),
        odds = TextEditingController(),
        sport = l?.sport ?? 'Soccer',
        status = l?.status ?? BetStatus.pending;
  final TextEditingController selection, event, odds;
  String sport;
  BetStatus status;

  void dispose() {
    selection.dispose();
    event.dispose();
    odds.dispose();
  }
}

class BetFormPage extends StatefulWidget {
  const BetFormPage({super.key, required this.store, this.bet, this.template});
  final BankStore store;
  final Bet? bet;
  final Bet? template;

  @override
  State<BetFormPage> createState() => _BetFormPageState();
}

class _BetFormPageState extends State<BetFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _selection, _event, _stake, _odds, _book, _notes, _cashout;
  late String _sport, _date;
  late BetStatus _status;
  late BetType _type;
  final List<_Leg> _legs = [];

  Settings get _settings => widget.store.settings;
  bool get _isNew => widget.bet == null;
  bool get _parlay => _type == BetType.parlay;

  @override
  void initState() {
    super.initState();
    final b = widget.bet ?? widget.template;
    final lastSport = widget.store.bets.isEmpty ? 'Soccer' : widget.store.bets.first.sport;
    final stake = b != null && b.stake > 0 ? b.stake : _settings.unit;
    _type = b?.type ?? BetType.single;
    _selection = TextEditingController(text: b != null && !b.isParlay ? b.selection : '');
    _event = TextEditingController(text: b != null && !b.isParlay ? b.event : '');
    _stake = TextEditingController(text: stake > 0 ? _num(stake) : '');
    _odds = TextEditingController(text: b != null && !b.isParlay ? formatOdds(b.odds, _settings.oddsFormat) : '');
    _book = TextEditingController(text: b?.book ?? '');
    _notes = TextEditingController(text: widget.bet?.notes ?? '');
    _cashout = TextEditingController(text: widget.bet?.cashout != null ? _num(widget.bet!.cashout!) : '');
    _sport = b?.sport ?? lastSport;
    if (!sports.contains(_sport)) _sport = 'Other';
    _date = b?.date ?? isoDate(DateTime.now());
    _status = widget.bet?.status ?? BetStatus.pending;
    for (final l in b?.legs ?? const <BetLeg>[]) {
      _addLeg(l);
    }
    if (_parlay && _legs.length < 2) {
      while (_legs.length < 2) {
        _addLeg();
      }
    }
    for (final c in [_stake, _odds]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  void _addLeg([BetLeg? l]) {
    final leg = _Leg(l);
    if (l != null) leg.odds.text = formatOdds(l.odds, _settings.oddsFormat);
    if (l == null) leg.sport = _legs.isNotEmpty ? _legs.last.sport : _sport;
    leg.odds.addListener(_refresh);
    _legs.add(leg);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [_selection, _event, _stake, _odds, _book, _notes, _cashout]) {
      c.dispose();
    }
    for (final l in _legs) {
      l.dispose();
    }
    super.dispose();
  }

  double? get _stakeVal => double.tryParse(_stake.text.replaceAll(',', '.'));
  double? _parse(String s) => parseOdds(s, _settings.oddsFormat);

  List<BetLeg> get _builtLegs => [
        for (final l in _legs)
          BetLeg(
            selection: l.selection.text.trim(),
            event: l.event.text.trim(),
            sport: l.sport,
            odds: _parse(l.odds.text) ?? 1,
            status: l.status,
          ),
      ];

  /// Combined decimal odds, or null while incomplete.
  double? get _oddsVal {
    if (!_parlay) return _parse(_odds.text);
    if (_legs.length < 2 || _legs.any((l) => _parse(l.odds.text) == null)) return null;
    return parlayOdds(_builtLegs);
  }

  void _setType(BetType t) {
    setState(() {
      _type = t;
      if (_parlay && _legs.isEmpty) {
        // Carry what's already typed into the first leg.
        _addLeg(BetLeg(
          selection: _selection.text.trim(),
          event: _event.text.trim(),
          sport: _sport,
          odds: _parse(_odds.text) ?? 1,
        ));
        if (_parse(_odds.text) == null) _legs.first.odds.text = '';
        _addLeg();
      }
    });
  }

  void _legStatusChanged() {
    final derived = parlayStatus(_builtLegs);
    setState(() {
      if (derived != BetStatus.pending || _status != BetStatus.cashout) _status = derived;
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = isoDate(d));
  }

  Bet _build() {
    final legs = _parlay ? _builtLegs : const <BetLeg>[];
    final legSports = legs.map((l) => l.sport).toSet();
    return Bet(
      id: widget.bet?.id,
      type: _type,
      selection: _parlay ? '${legs.length}-leg parlay' : _selection.text.trim(),
      event: _parlay ? '' : _event.text.trim(),
      sport: _parlay ? (legSports.length == 1 ? legSports.first : 'Mixed') : _sport,
      date: _date,
      stake: _stakeVal ?? 0,
      odds: double.parse((_oddsVal ?? 1).toStringAsFixed(4)),
      book: _book.text.trim(),
      status: _status,
      cashout: _status == BetStatus.cashout ? double.tryParse(_cashout.text.replaceAll(',', '.')) : null,
      notes: _notes.text.trim(),
      created: widget.bet?.created ?? DateTime.now().toIso8601String(),
      legs: legs,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_oddsVal == null || _oddsVal! <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the odds')));
      return;
    }
    await widget.store.saveBet(_build());
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

  String? _oddsValidator(String? v) =>
      _parse(v ?? '') != null ? null : (_settings.oddsFormat == OddsFormat.american ? 'Use +150 or -110' : 'Above 1.00');

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(_settings);
    final theme = Theme.of(context);
    final american = _settings.oddsFormat == OddsFormat.american;
    final oddsLabel = american ? 'Odds (+150 / -110)' : 'Odds (e.g. 2.50)';
    final s = _stakeVal, o = _oddsVal;
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? (widget.template != null ? 'Log shared bet' : 'Log a bet') : 'Edit bet'),
        actions: [
          IconButton(
            tooltip: 'Share link',
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              if (_oddsVal == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add the odds first')));
                return;
              }
              showShareBet(context, widget.store, _build());
            },
          ),
          if (!_isNew) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Section(
              title: 'Bet type',
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<BetType>(
                  segments: [
                    for (final t in BetType.values) ButtonSegment(value: t, label: Text(t.label)),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => _setType(v.first),
                ),
              ),
            ),
            if (!_parlay)
              _Section(
                title: 'Selection',
                child: Column(children: [
                  TextFormField(
                    controller: _selection,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _type == BetType.system ? 'System (e.g. Trixie, 2/3)' : 'Selection',
                      hintText: 'e.g. Arsenal to win, Over 2.5 goals',
                      prefixIcon: const Icon(Icons.sports_score),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Add what you bet on' : null,
                  ),
                  gap,
                  TextFormField(
                    controller: _event,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Event (optional)', hintText: 'e.g. Arsenal vs Chelsea', prefixIcon: Icon(Icons.event)),
                  ),
                  gap,
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: _SportField(value: _sport, onChanged: (v) => setState(() => _sport = v)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _odds,
                        keyboardType: TextInputType.numberWithOptions(decimal: true, signed: american),
                        decoration: InputDecoration(labelText: oddsLabel),
                        validator: _oddsValidator,
                      ),
                    ),
                  ]),
                ]),
              )
            else
              _Section(
                title: 'Parlay legs',
                trailing: o == null
                    ? null
                    : Text('Combined ${formatOdds(o, _settings.oddsFormat)}',
                        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                child: Column(children: [
                  for (var i = 0; i < _legs.length; i++) ...[
                    _LegCard(
                      key: ObjectKey(_legs[i]),
                      index: i,
                      leg: _legs[i],
                      oddsLabel: oddsLabel,
                      american: american,
                      oddsValidator: _oddsValidator,
                      showResult: !_isNew || _legs.any((l) => l.status != BetStatus.pending),
                      onRemove: _legs.length > 2
                          ? () => setState(() => _legs.removeAt(i).dispose())
                          : null,
                      onChanged: _refresh,
                      onStatus: _legStatusChanged,
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _addLeg()),
                      icon: const Icon(Icons.add),
                      label: const Text('Add leg'),
                    ),
                  ),
                ]),
              ),
            _Section(
              title: 'Stake',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                  controller: _stake,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Stake (${_settings.currency})',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  validator: (_) => (_stakeVal ?? 0) > 0 ? null : 'Enter a stake above zero',
                ),
                if (_settings.unit > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Text('Units', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          for (final u in const [0.5, 1, 2, 3, 5])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                visualDensity: VisualDensity.compact,
                                tooltip: fmt.money(u * _settings.unit),
                                label: Text('${_num(u.toDouble())}u'),
                                onPressed: () => _stake.text = _num(u * _settings.unit),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            _Section(
              title: 'Details',
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.calendar_today, size: 18)),
                      child: Text(Fmt.date(_date)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _book,
                    decoration: const InputDecoration(labelText: 'Bookmaker'),
                  ),
                ),
              ]),
            ),
            _Section(
              title: 'Result',
              trailing: _parlay ? Text('Set from the legs', style: theme.textTheme.bodySmall) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final st in BetStatus.values)
                    ChoiceChip(
                      label: Text(st.label),
                      selected: _status == st,
                      selectedColor: BankColors.forStatus(context, st).withValues(alpha: 0.2),
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
              ]),
            ),
            _Section(
              title: 'Notes',
              child: TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'Why you took it, tipster, anything to remember'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SlipBar(
        fmt: fmt,
        stake: s,
        odds: o,
        oddsText: o == null ? '–' : formatOdds(o, _settings.oddsFormat),
        saveLabel: _isNew ? 'Log bet' : 'Save',
        onSave: _save,
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
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1, color: theme.colorScheme.primary)),
            const Spacer(),
            ?trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _SportField extends StatelessWidget {
  const _SportField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: sports.contains(value) ? value : 'Other',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sport'),
        items: [for (final sp in sports) DropdownMenuItem(value: sp, child: Text(sp, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => onChanged(v ?? value),
      );
}

class _LegCard extends StatelessWidget {
  const _LegCard({
    super.key,
    required this.index,
    required this.leg,
    required this.oddsLabel,
    required this.american,
    required this.oddsValidator,
    required this.showResult,
    required this.onRemove,
    required this.onChanged,
    required this.onStatus,
  });
  final int index;
  final _Leg leg;
  final String oddsLabel;
  final bool american;
  final FormFieldValidator<String> oddsValidator;
  final bool showResult;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const gap = SizedBox(height: 10);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primaryContainer,
            child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text('Leg ${index + 1}', style: theme.textTheme.titleSmall),
          const Spacer(),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove leg',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            )
          else
            const SizedBox(height: 40),
        ]),
        TextFormField(
          controller: leg.selection,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Selection', isDense: true),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Add the selection' : null,
        ),
        gap,
        TextFormField(
          controller: leg.event,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Event (optional)', isDense: true),
        ),
        gap,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _SportField(
              value: leg.sport,
              onChanged: (v) {
                leg.sport = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: leg.odds,
              keyboardType: TextInputType.numberWithOptions(decimal: true, signed: american),
              decoration: InputDecoration(labelText: oddsLabel, isDense: true),
              validator: oddsValidator,
            ),
          ),
        ]),
        if (showResult) ...[
          gap,
          Wrap(spacing: 6, children: [
            for (final st in const [BetStatus.pending, BetStatus.won, BetStatus.lost, BetStatus.voided])
              ChoiceChip(
                label: Text(st.label),
                visualDensity: VisualDensity.compact,
                selected: leg.status == st,
                selectedColor: BankColors.forStatus(context, st).withValues(alpha: 0.2),
                onSelected: (_) {
                  leg.status = st;
                  onStatus();
                },
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Sticky bottom bar: what the slip pays, and the save button.
class _SlipBar extends StatelessWidget {
  const _SlipBar({
    required this.fmt,
    required this.stake,
    required this.odds,
    required this.oddsText,
    required this.saveLabel,
    required this.onSave,
  });
  final Fmt fmt;
  final double? stake, odds;
  final String oddsText, saveLabel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = stake != null && stake! > 0 && odds != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ok ? 'Returns ${fmt.money(stake! * odds!)}' : 'Returns –',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  ok
                      ? 'Profit ${fmt.money(stake! * (odds! - 1))} · odds $oddsText · ${(100 / odds!).toStringAsFixed(1)}% implied'
                      : 'Add stake and odds',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onSave, child: Text(saveLabel)),
          ]),
        ),
      ),
    );
  }
}
