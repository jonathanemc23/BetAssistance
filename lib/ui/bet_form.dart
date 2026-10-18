import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/markets.dart';
import '../logic/stats.dart';
import 'format.dart';
import 'market_sheet.dart';
import 'themes.dart';
import 'share_ui.dart';

/// Opens the bet form: [bet] edits an existing bet, [template] pre-fills a
/// new one (from a share link or "log again"). Shows the result as a snackbar.
Future<void> openBetForm(BuildContext context, BankStore store, {Bet? bet, Bet? template}) async {
  final messenger = ScaffoldMessenger.of(context);
  final msg = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => BetFormPage(store: store, bet: bet, template: template),
    ),
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
  late String _market;
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
    _market = b?.market ?? '';
    _selection = TextEditingController(text: b != null && !b.isParlay ? b.selection : '');
    _event = TextEditingController(text: b != null && !b.isParlay ? b.event : '');
    _stake = TextEditingController(text: stake > 0 ? _num(stake) : '');
    _odds = TextEditingController(
      text: b != null && !b.isParlay && b.odds > 1 ? formatOdds(b.odds, _settings.oddsFormat) : '',
    );
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
    if (l != null && l.odds > 1) leg.odds.text = formatOdds(l.odds, _settings.oddsFormat);
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
        _addLeg(
          BetLeg(
            selection: _selection.text.trim(),
            event: _event.text.trim(),
            sport: _sport,
            odds: _parse(_odds.text) ?? 1,
          ),
        );
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
      market: _parlay ? 'parlay' : (_market.isNotEmpty ? _market : marketOf(_selection.text)),
      matchId: _parlay ? null : _source?.matchId,
      leagueSlug: _parlay ? null : _source?.leagueSlug,
      leagueName: _parlay ? null : _source?.leagueName,
      kickoff: _parlay ? null : _source?.kickoff,
    );
  }

  /// Where the bet came from (the match it was picked from, if any).
  Bet? get _source => widget.bet ?? widget.template;

  Future<void> _chooseMarket() async {
    final pick = await showMarketSheet(
      context,
      event: _event.text,
      format: _settings.oddsFormat,
      initialMarket: _market.isEmpty ? null : _market,
    );
    if (pick == null) return;
    setState(() {
      _market = pick.market;
      _selection.text = pick.selection;
    });
  }

  Future<void> _chooseLegMarket(_Leg leg) async {
    final pick = await showMarketSheet(context, event: leg.event.text, format: _settings.oddsFormat);
    if (pick != null) setState(() => leg.selection.text = pick.selection);
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

  String? _oddsValidator(String? v) => _parse(v ?? '') != null
      ? null
      : (_settings.oddsFormat == OddsFormat.american ? 'Use +150 or -110' : 'Above 1.00');

  void _setDateOffset(int days) => setState(() => _date = isoDate(DateTime.now().subtract(Duration(days: days))));

  @override
  Widget build(BuildContext context) {
    final fmt = Fmt(_settings);
    final theme = Theme.of(context);
    final american = _settings.oddsFormat == OddsFormat.american;
    final oddsHint = american ? '+150' : '2.50';
    final s = _stakeVal, o = _oddsVal;
    final ready = s != null && s > 0 && o != null;
    const gap = SizedBox(height: 12);
    final today = isoDate(DateTime.now());
    final yesterday = isoDate(DateTime.now().subtract(const Duration(days: 1)));

    return Scaffold(
      body: Form(
        key: _form,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _SlipHeader(
                title: _isNew ? (widget.template != null ? 'New bet' : 'Log a bet') : 'Edit bet',
                type: _type,
                onType: _setType,
                returns: ready ? fmt.money(s * o) : '–',
                chips: [
                  'Odds ${o == null ? '–' : formatOdds(o, _settings.oddsFormat)}',
                  'Stake ${s != null && s > 0 ? fmt.money(s) : '–'}',
                  if (ready) 'Profit ${fmt.money(s * (o - 1))}',
                  if (o != null) '${(100 / o).toStringAsFixed(1)}% implied',
                ],
                onShare: () {
                  if (_oddsVal == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add the odds first')));
                    return;
                  }
                  showShareBet(context, widget.store, _build());
                },
                onDelete: _isNew ? null : _delete,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList.list(
                children: [
                  if (!_parlay) ...[
                    const _Label('What did you bet on?'),
                    TextFormField(
                      controller: _selection,
                      textCapitalization: TextCapitalization.sentences,
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        hintText: _type == BetType.system
                            ? 'System, e.g. Trixie 2/3'
                            : 'Selection, e.g. Arsenal to win',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Add what you bet on' : null,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.list_alt, size: 18),
                          label: Text(
                            _market.isEmpty || _market == 'other'
                                ? 'Choose a market: handicap, overs, corners…'
                                : 'Market: ${marketById(_market).label}',
                          ),
                          onPressed: _chooseMarket,
                        ),
                      ),
                    ),
                    gap,
                    TextFormField(
                      controller: _event,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Event (optional), e.g. Arsenal vs Chelsea',
                        prefixIcon: Icon(Icons.stadium_outlined),
                      ),
                    ),
                    gap,
                    _SportPicker(value: _sport, onChanged: (v) => setState(() => _sport = v)),
                    const _Label('Odds'),
                    _BigField(
                      controller: _odds,
                      hint: oddsHint,
                      icon: Icons.trending_up,
                      signed: american,
                      validator: _oddsValidator,
                    ),
                  ] else ...[
                    _Label('Legs', trailing: o == null ? null : 'Combined ${formatOdds(o, _settings.oddsFormat)}'),
                    for (var i = 0; i < _legs.length; i++)
                      _LegCard(
                        key: ObjectKey(_legs[i]),
                        index: i,
                        last: i == _legs.length - 1,
                        leg: _legs[i],
                        oddsHint: oddsHint,
                        american: american,
                        oddsValidator: _oddsValidator,
                        showResult: !_isNew || _legs.any((l) => l.status != BetStatus.pending),
                        onRemove: _legs.length > 2 ? () => setState(() => _legs.removeAt(i).dispose()) : null,
                        onChanged: _refresh,
                        onStatus: _legStatusChanged,
                        onMarket: () => _chooseLegMarket(_legs[i]),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _addLeg()),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add leg'),
                      ),
                    ),
                  ],
                  const _Label('Stake'),
                  _BigField(
                    controller: _stake,
                    hint: '0',
                    icon: Icons.payments_outlined,
                    suffix: _settings.currency,
                    validator: (_) => (_stakeVal ?? 0) > 0 ? null : 'Enter a stake above zero',
                  ),
                  if (_settings.unit > 0) ...[
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final u in const [0.5, 1, 2, 3, 5])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _Pill(
                                label: '${_num(u.toDouble())}u',
                                selected: _stakeVal == u * _settings.unit,
                                onTap: () => _stake.text = _num(u * _settings.unit),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const _Label('When and where'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(label: 'Today', selected: _date == today, onTap: () => _setDateOffset(0)),
                      _Pill(label: 'Yesterday', selected: _date == yesterday, onTap: () => _setDateOffset(1)),
                      _Pill(
                        label: _date == today || _date == yesterday ? 'Other date' : Fmt.date(_date),
                        icon: Icons.calendar_today,
                        selected: _date != today && _date != yesterday,
                        onTap: _pickDate,
                      ),
                    ],
                  ),
                  gap,
                  TextFormField(
                    controller: _book,
                    decoration: const InputDecoration(
                      hintText: 'Bookmaker (optional)',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  _Label('Result', trailing: _parlay ? 'Set from the legs' : null),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final st in BetStatus.values)
                        _Pill(
                          label: st.label,
                          color: BankColors.forStatus(context, st),
                          selected: _status == st,
                          onTap: () => setState(() => _status = st),
                        ),
                    ],
                  ),
                  if (_status == BetStatus.cashout) ...[
                    gap,
                    TextFormField(
                      controller: _cashout,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'Cash-out amount received'),
                      validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1) >= 0
                          ? null
                          : 'Enter the amount you received',
                    ),
                  ],
                  const _Label('Notes'),
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(hintText: 'Why you took it, tipster, anything to remember'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: _GradientButton(
            label: _isNew ? 'Log bet' : 'Save changes',
            sub: ready ? 'Returns ${fmt.money(s * o)}' : null,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

const _sportEmoji = {
  'Soccer': '⚽',
  'Basketball': '🏀',
  'American Football': '🏈',
  'Tennis': '🎾',
  'Baseball': '⚾',
  'Ice Hockey': '🏒',
  'MMA': '🥋',
  'Boxing': '🥊',
  'Cricket': '🏏',
  'Golf': '⛳',
  'Esports': '🎮',
  'Other': '🎯',
};

/// Gradient header: title, bet type switch and the live slip numbers.
class _SlipHeader extends StatelessWidget {
  const _SlipHeader({
    required this.title,
    required this.type,
    required this.onType,
    required this.returns,
    required this.chips,
    required this.onShare,
    required this.onDelete,
  });
  final String title;
  final BetType type;
  final ValueChanged<BetType> onType;
  final String returns;
  final List<String> chips;
  final VoidCallback onShare;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = HeroColors.of(context);
    final fg = hero.onGradient;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: hero.gradient),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BackButton(color: fg),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(tooltip: 'Share link', color: fg, icon: const Icon(Icons.ios_share), onPressed: onShare),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Delete',
                      color: fg,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onDelete,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: fg.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    children: [
                      for (final t in BetType.values)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => onType(t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: t == type ? fg : Colors.transparent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                t.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: t == type ? hero.gradient.last : fg,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POTENTIAL RETURN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.75),
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      returns,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: fg.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              c,
                              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
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

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Text(text, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

/// Large numeric field for odds and stake.
class _BigField extends StatelessWidget {
  const _BigField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.validator,
    this.suffix,
    this.signed = false,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? suffix;
  final bool signed;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: signed),
      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixText: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      validator: validator,
    );
  }
}

/// Rounded selectable pill used for units, dates and results.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, this.color, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    // Status colours are mid-tones that carry white; the theme's primary
    // brings its own contrasting colour.
    final on = color == null ? cs.onPrimary : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? on : cs.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: selected ? on : cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SportPicker extends StatelessWidget {
  const _SportPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final sp in sports)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(sp),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 76,
                  decoration: BoxDecoration(
                    color: sp == value ? cs.primaryContainer : cs.surfaceContainerHighest,
                    border: Border.all(color: sp == value ? cs.primary : Colors.transparent, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_sportEmoji[sp] ?? '🎯', style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 4),
                      Text(
                        sp == 'American Football' ? 'NFL' : sp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sp == value ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegCard extends StatelessWidget {
  const _LegCard({
    super.key,
    required this.index,
    required this.last,
    required this.leg,
    required this.oddsHint,
    required this.american,
    required this.oddsValidator,
    required this.showResult,
    required this.onRemove,
    required this.onChanged,
    required this.onStatus,
    required this.onMarket,
  });
  final int index;
  final bool last;
  final _Leg leg;
  final String oddsHint;
  final bool american;
  final FormFieldValidator<String> oddsValidator;
  final bool showResult;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;
  final VoidCallback onStatus;
  final VoidCallback onMarket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline: numbered dot with a line to the next leg.
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800),
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, color: cs.primary.withValues(alpha: 0.3))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_sportEmoji[leg.sport] ?? '🎯', style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: sports.contains(leg.sport) ? leg.sport : 'Other',
                            isDense: true,
                            isExpanded: true,
                            style: theme.textTheme.labelLarge,
                            items: [for (final sp in sports) DropdownMenuItem(value: sp, child: Text(sp))],
                            onChanged: (v) {
                              leg.sport = v ?? leg.sport;
                              onChanged();
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Choose a market',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.list_alt, size: 18),
                        onPressed: onMarket,
                      ),
                      if (onRemove != null)
                        IconButton(
                          tooltip: 'Remove leg',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: onRemove,
                        )
                      else
                        const SizedBox(height: 40),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: leg.selection,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Selection', isDense: true),
                          validator: (v) => (v ?? '').trim().isEmpty ? 'Add the selection' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 92,
                        child: TextFormField(
                          controller: leg.odds,
                          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: american),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          decoration: InputDecoration(hintText: oddsHint, isDense: true),
                          validator: oddsValidator,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextFormField(
                      controller: leg.event,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Event (optional)', isDense: true),
                    ),
                  ),
                  if (showResult) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final st in const [BetStatus.pending, BetStatus.won, BetStatus.lost, BetStatus.voided])
                          _Pill(
                            label: st.label,
                            color: BankColors.forStatus(context, st),
                            selected: leg.status == st,
                            onTap: () {
                              leg.status = st;
                              onStatus();
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap, this.sub});
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, cs.secondary, 0.6)!]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(color: cs.onPrimary, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sub ?? '',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward, color: cs.onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
