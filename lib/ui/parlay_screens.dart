import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/parlay.dart';
import '../data/store.dart';
import '../logic/leg_linker.dart';
import '../logic/parlay_check.dart';
import '../logic/stats.dart';
import 'bet_form.dart';
import 'format.dart';
import 'market_sheet.dart';
import 'matches_screen.dart';
import 'share_ui.dart';
import 'slip_import.dart';
import 'themes.dart';

/// Parlay builder: the user's saved parlays, newest activity first.
class ParlaysPage extends StatelessWidget {
  const ParlaysPage({super.key, required this.store, required this.api});
  final BankStore store;
  final FixturesApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Parlay builder'))),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'slip',
          onPressed: () => importSlip(context, store: store, api: api),
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(tr('From screenshot')),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'new',
          onPressed: () async {
            final p = await store.newParlay();
            if (context.mounted) await openParlay(context, store: store, api: api, parlay: p);
          },
          icon: const Icon(Icons.add),
          label: Text(tr('New parlay')),
        ),
      ]),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = store.parlays;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.account_tree_outlined, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(tr('Build your parlays'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    tr('Add picks from the match list or matches that are not listed, or load a screenshot of a slip from any betting site. Check them, share them and mark the result.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 168),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ParlayTile(
              parlay: list[i],
              format: store.settings.oddsFormat,
              onTap: () => openParlay(context, store: store, api: api, parlay: list[i]),
            ),
          );
        },
      ),
    );
  }
}

Future<void> openParlay(BuildContext context,
        {required BankStore store, required FixturesApi api, required Parlay parlay, ParlayChecker? checker}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ParlayPage(store: store, api: api, parlayId: parlay.id!, checker: checker),
    ));

/// What tapping a price does: log it as a single bet, or add it to a parlay.
Future<void> pickSelection(BuildContext context,
    {required BankStore store, required FixturesApi api, required Match match, required String selection, required double odds}) async {
  final current = store.currentParlay;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final theme = Theme.of(c);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selection, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('${match.title} · ${formatOdds(odds, store.settings.oddsFormat)}', style: theme.textTheme.bodySmall),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(tr('Log as a single bet')),
            onTap: () => Navigator.pop(c, 'single'),
          ),
          if (current != null)
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(tr('Add to {parlay}', {'parlay': current.name})),
              subtitle: Text(trn(current.legs.length, '{n} pick so far', '{n} picks so far')),
              onTap: () => Navigator.pop(c, 'add'),
            ),
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(tr('Start a new parlay')),
            onTap: () => Navigator.pop(c, 'new'),
          ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'single') {
    return openBetForm(context, store, template: match.toBetTemplate(selection: selection, odds: odds), api: api);
  }
  final leg = ParlayLeg.fromMatch(match, selection, odds);
  final p = choice == 'add' && current != null ? await store.addLeg(current, leg) : await store.newParlay(legs: [leg]);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(trn(p.legs.length, 'Added to {parlay} · {n} pick', 'Added to {parlay} · {n} picks', {'parlay': p.name})),
    duration: const Duration(seconds: 4),
    persist: false,
    action: SnackBarAction(
      label: tr('Open'),
      onPressed: () => openParlay(context, store: store, api: api, parlay: p),
    ),
  ));
}

class _ParlayTile extends StatelessWidget {
  const _ParlayTile({required this.parlay, required this.format, required this.onTap});
  final Parlay parlay;
  final OddsFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = parlay;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(status: p.status),
                  if (p.check != null) ...[const SizedBox(width: 6), _RiskPill(risk: p.check!.risk)],
                ]),
                const SizedBox(height: 4),
                Text(
                  p.legs.isEmpty ? tr('No picks yet') : p.legs.map((l) => trPick(l.selection)).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(p.legs.isEmpty ? '–' : formatOdds(p.odds, format),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
              Text(trn(p.legs.length, '{n} leg', '{n} legs'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// One parlay: its picks, the stake, the check, sharing and the result.
class ParlayPage extends StatefulWidget {
  const ParlayPage({super.key, required this.store, required this.api, required this.parlayId, this.checker});
  final BankStore store;
  final FixturesApi api;
  final int parlayId;
  final ParlayChecker? checker;

  @override
  State<ParlayPage> createState() => _ParlayPageState();
}

class _ParlayPageState extends State<ParlayPage> {
  late final ParlayChecker _checker = widget.checker ?? DataParlayChecker(widget.api);
  late final TextEditingController _stake;
  bool _checking = false;

  BankStore get store => widget.store;
  Parlay? get _parlay => store.parlayById(widget.parlayId);

  @override
  void initState() {
    super.initState();
    final s = _parlay?.stake ?? 0;
    _stake = TextEditingController(text: s > 0 ? _num(s) : '');
  }

  @override
  void dispose() {
    _stake.dispose();
    super.dispose();
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _addFromMatches(Parlay p) async {
    final leg = await Navigator.of(context).push<ParlayLeg>(MaterialPageRoute(
      builder: (c) => Scaffold(
        appBar: AppBar(title: Text(tr('Pick a selection'))),
        body: MatchesTabs(
          store: store,
          api: widget.api,
          onPick: (m, sel, odds) => Navigator.pop(c, ParlayLeg.fromMatch(m, sel, odds)),
        ),
      ),
    ));
    if (leg != null) await store.addLeg(_parlay ?? p, leg);
  }

  Future<void> _addExternal(Parlay p) async {
    final leg = await showModalBottomSheet<ParlayLeg>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExternalLegSheet(format: store.settings.oddsFormat),
    );
    if (leg == null) return;
    final linked = (await linkLegs(widget.api, [leg])).single;
    await store.addLeg(_parlay ?? p, linked);
  }

  Future<void> _check(Parlay p) async {
    setState(() => _checking = true);
    try {
      // Picks typed in or read from a slip are matched to real fixtures first.
      final legs = await linkLegs(widget.api, p.legs);
      if (!identical(legs, p.legs)) p = p.copyWith(legs: legs);
      final c = await _checker.check(p);
      await store.saveParlay((_parlay ?? p).copyWith(legs: legs, check: c));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _rename(Parlay p) async {
    final ctrl = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Rename parlay')),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: tr('Name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(tr('Save'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await store.saveParlay(p.copyWith(name: name));
  }

  Future<void> _delete(Parlay p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete this parlay?')),
        content: Text(trn(p.legs.length, '{parlay} and its {n} pick will be removed.', '{parlay} and its {n} picks will be removed.', {'parlay': p.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    await store.deleteParlay(p);
  }

  Bet _asBet(Parlay p) {
    final now = DateTime.now();
    return p.toBet(date: isoDate(now), created: now.toIso8601String());
  }

  Future<void> _share(Parlay p) async {
    final fmt = Fmt(store.settings);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(tr('Share as a link')),
            subtitle: Text(tr('Opens in BetPilot ready to log')),
            onTap: () => Navigator.pop(c, 'link'),
          ),
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(tr('Share picks and check as text')),
            subtitle: Text(p.check == null ? tr('Run the check first to include it') : tr('Includes the latest check')),
            onTap: () => Navigator.pop(c, 'text'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'link') return showShareBet(context, store, _asBet(p));
    final o = store.settings.oddsFormat;
    final text = StringBuffer(trn(p.legs.length, '{parlay}: {n} pick at {odds}', '{parlay}: {n} picks at {odds}',
        {'parlay': p.name, 'odds': formatOdds(p.odds, o)}));
    if (p.stake > 0) {
      text.write(tr(', {stake} to return {returns}', {'stake': fmt.money(p.stake), 'returns': fmt.money(p.potentialReturn)}));
    }
    text.writeln();
    for (final (i, l) in p.legs.indexed) {
      final c = p.check != null && i < p.check!.legs.length ? ' (${p.check!.legs[i].verdict})' : '';
      text.writeln('${i + 1}. ${trPick(l.selection)} @ ${formatOdds(l.odds, o)}${l.event.isEmpty ? '' : ' · ${l.event}'}$c');
    }
    if (p.check != null) {
      text.writeln('\n${tr('Check ({risk} risk):', {'risk': riskLabel(p.check!.risk).toLowerCase()})}');
      for (final s in p.check!.summary) {
        text.writeln('• $s');
      }
    }
    text.write('\n${tr('Built with BetPilot')}');
    await SharePlus.instance.share(ShareParams(text: text.toString(), subject: p.name));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = _parlay;
        if (p == null) return const Scaffold(body: SizedBox());
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final o = store.settings.oddsFormat;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              IconButton(tooltip: tr('Rename'), icon: const Icon(Icons.edit_outlined), onPressed: () => _rename(p)),
              IconButton(
                tooltip: tr('Share parlay'),
                icon: const Icon(Icons.share_outlined),
                onPressed: p.legs.isEmpty ? null : () => _share(p),
              ),
              IconButton(tooltip: tr('Delete parlay'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(p)),
            ],
          ),
          body: ListView(key: const Key('parlay-page'), padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            _SlipHeader(parlay: p, store: store, stake: _stake),
            const SizedBox(height: 18),
            Row(children: [
              Text(tr('Selections'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${p.legs.length}', style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 8),
            if (p.legs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('Add picks from the match list, or type in a match that is not listed.'),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final (i, l) in p.legs.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LegCard(
                  leg: l,
                  index: i,
                  format: o,
                  check: p.check != null && i < p.check!.legs.length && p.check!.legs[i].selection == l.selection
                      ? p.check!.legs[i]
                      : null,
                  onStatus: (s) => store.setLegStatus(p, i, s),
                  onRemove: () => store.removeLeg(p, i),
                ),
              ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addFromMatches(p),
                  icon: const Icon(Icons.sports_soccer),
                  label: Text(tr('From matches')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _addExternal(p),
                  icon: const Icon(Icons.edit_note),
                  label: Text(tr('Other match')),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            Row(children: [
              Text(tr('Check'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (p.check != null) _RiskPill(risk: p.check!.risk),
            ]),
            const SizedBox(height: 8),
            if (p.check != null) _CheckCard(check: p.check!, stale: _isStale(p)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: p.legs.isEmpty || _checking ? null : () => _check(p),
              icon: _checking
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : const Icon(Icons.fact_check_outlined),
              label: Text(p.check == null ? tr('Check parlay') : tr('Check again')),
            ),
            const SizedBox(height: 22),
            Text(tr('Result'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<BetStatus>(
              segments: [
                ButtonSegment(value: BetStatus.pending, label: Text(tr('Open'))),
                ButtonSegment(value: BetStatus.won, label: Text(tr('Won'))),
                ButtonSegment(value: BetStatus.lost, label: Text(tr('Lost'))),
              ],
              selected: {if (const [BetStatus.pending, BetStatus.won, BetStatus.lost].contains(p.status)) p.status},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) {
                if (s.isNotEmpty) store.setParlayStatus(p, s.first);
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: p.legs.isEmpty ? null : () => openBetForm(context, store, template: _asBet(p), api: widget.api),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(tr('Log in the bet register')),
            ),
          ]),
        );
      },
    );
  }

  /// The picks changed since the last check.
  bool _isStale(Parlay p) {
    final c = p.check!;
    return c.legs.length != p.legs.length || [for (var i = 0; i < c.legs.length; i++) c.legs[i].selection != p.legs[i].selection].any((x) => x);
  }
}

class _SlipHeader extends StatelessWidget {
  const _SlipHeader({required this.parlay, required this.store, required this.stake});
  final Parlay parlay;
  final BankStore store;
  final TextEditingController stake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = HeroColors.of(context);
    final fg = hero.onGradient;
    final p = parlay;
    final fmt = Fmt(store.settings);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: hero.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('COMBINED ODDS'), style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8), letterSpacing: 1)),
              Text(p.legs.isEmpty ? '–' : formatOdds(p.odds, store.settings.oddsFormat),
                  style: theme.textTheme.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
            ]),
          ),
          _StatusPill(status: p.status, onDark: true),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 130,
            child: TextField(
              controller: stake,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: fg, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                labelText: tr('Stake'),
                labelStyle: TextStyle(color: fg.withValues(alpha: 0.8)),
                fillColor: Colors.black.withValues(alpha: 0.18),
              ),
              onChanged: (v) {
                final s = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                store.saveParlay(p.copyWith(stake: s));
              },
            ),
          ),
          const SizedBox(width: 12),
          // Large amounts (e.g. pesos) shrink rather than overflow.
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr('Returns'), style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8))),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(p.stake > 0 && p.legs.isNotEmpty ? fmt.money(p.potentialReturn) : '–',
                    style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _LegCard extends StatelessWidget {
  const _LegCard({
    required this.leg,
    required this.index,
    required this.format,
    required this.check,
    required this.onStatus,
    required this.onRemove,
  });
  final ParlayLeg leg;
  final int index;
  final OddsFormat format;
  final LegCheck? check;
  final ValueChanged<BetStatus> onStatus;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = leg;
    final when = l.kickoff == null ? '' : ' · ${DateFormat.MMMd().add_Hm().format(l.kickoff!.toLocal())}';
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: cs.primaryContainer,
              child: Text('${index + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trPick(l.selection),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Row(children: [
                  Icon(l.isLinked ? Icons.sports_soccer : Icons.edit_note, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${l.event.isEmpty ? l.sport : l.event}$when',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ]),
            ),
            Text(formatOdds(l.odds, format),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
            PopupMenuButton<String>(
              tooltip: tr('Leg options'),
              onSelected: (v) => v == 'remove' ? onRemove() : onStatus(BetStatusX.parse(v)),
              itemBuilder: (_) => [
                for (final s in [BetStatus.pending, BetStatus.won, BetStatus.lost, BetStatus.voided])
                  CheckedPopupMenuItem(value: s.dbValue, checked: l.status == s, child: Text(s == BetStatus.pending ? tr('Open') : s.label)),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'remove', child: Text(tr('Remove pick'))),
              ],
            ),
          ]),
          if (l.status != BetStatus.pending || check != null)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 6, right: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if (l.status != BetStatus.pending) _StatusPill(status: l.status),
                if (check != null) _VerdictPill(check: check!),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check, required this.stale});
  final ParlayCheck check;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final when = DateTime.tryParse(check.checked);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('The picks changed since this check. Check again to update it.'),
                style: theme.textTheme.bodySmall?.copyWith(color: BankColors.pending(context))),
          ),
        for (final s in check.summary)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(s, style: theme.textTheme.bodyMedium),
          ),
        for (final l in check.legs) ...[
          const Divider(height: 18),
          Row(children: [
            Expanded(
              child: Text(trPick(l.selection),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            _VerdictPill(check: l),
          ]),
          const SizedBox(height: 4),
          for (final line in l.lines)
            Text(line, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
        Text('${check.source == 'Match data' ? tr('Match data') : check.source}${when == null ? '' : ' · ${DateFormat.MMMd().add_Hm().format(when.toLocal())}'}',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, this.onDark = false});
  final BetStatus status;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final label = status == BetStatus.pending ? tr('OPEN') : status.label.toUpperCase();
    return _Pill(label, onDark ? HeroColors.of(context).onGradient : BankColors.forStatus(context, status));
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.risk});
  final String risk;

  @override
  Widget build(BuildContext context) => _Pill(
        tr('{risk} RISK', {'risk': riskLabel(risk).toUpperCase()}),
        switch (risk) {
          'Low' => BankColors.win(context),
          'High' => BankColors.loss(context),
          _ => BankColors.pending(context),
        },
      );
}

class _VerdictPill extends StatelessWidget {
  const _VerdictPill({required this.check});
  final LegCheck check;

  @override
  Widget build(BuildContext context) => _Pill(
        check.verdict,
        switch (check.tone) {
          LegTone.good => BankColors.win(context),
          LegTone.warning => BankColors.loss(context),
          LegTone.neutral => BankColors.neutral(context),
        },
      );
}

/// Form for a pick on a match that isn't in the list.
class _ExternalLegSheet extends StatefulWidget {
  const _ExternalLegSheet({required this.format});
  final OddsFormat format;

  @override
  State<_ExternalLegSheet> createState() => _ExternalLegSheetState();
}

class _ExternalLegSheetState extends State<_ExternalLegSheet> {
  final _form = GlobalKey<FormState>();
  final _event = TextEditingController();
  final _selection = TextEditingController();
  final _odds = TextEditingController();
  String _sport = 'Soccer';

  @override
  void dispose() {
    _event.dispose();
    _selection.dispose();
    _odds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Add another match'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(tr('For matches that are not in the list.'), style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          TextFormField(
            controller: _event,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Match'), hintText: tr('e.g. Millonarios vs Nacional')),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _selection,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Selection'),
              hintText: tr('e.g. Millonarios to win'),
              suffixIcon: IconButton(
                tooltip: tr('Choose a market'),
                icon: const Icon(Icons.list_alt),
                onPressed: () async {
                  final pick = await showMarketSheet(context, event: _event.text, format: widget.format);
                  if (pick != null) _selection.text = pick.selection;
                },
              ),
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? tr('Enter the pick') : null,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _odds,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                    labelText: tr('Odds'), hintText: widget.format == OddsFormat.american ? '+150' : '2.50'),
                validator: (v) => parseOdds(v ?? '', widget.format) == null ? tr('Enter valid odds') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sport,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Sport')),
                items: [for (final s in sports) DropdownMenuItem(value: s, child: Text(sportLabel(s)))],
                onChanged: (v) => setState(() => _sport = v ?? _sport),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('Add pick')),
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                context,
                ParlayLeg(
                  selection: _selection.text.trim(),
                  event: _event.text.trim(),
                  sport: _sport,
                  odds: parseOdds(_odds.text, widget.format)!,
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}
