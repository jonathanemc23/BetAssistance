import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../data/live_alert_service.dart';
import '../data/models.dart';
import '../data/push_alerts.dart';
import '../data/store.dart';
import '../logic/claude_assistant.dart';
import 'format.dart';
import 'profile.dart';
import 'themes.dart';

/// Bottom sheet to record a deposit or withdrawal.
Future<String?> showTxSheet(BuildContext context, BankStore store, TxKind kind) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _TxSheet(store: store, kind: kind),
  );
}

class _TxSheet extends StatefulWidget {
  const _TxSheet({required this.store, required this.kind});
  final BankStore store;
  final TxKind kind;
  @override
  State<_TxSheet> createState() => _TxSheetState();
}

class _TxSheetState extends State<_TxSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = isoDate(DateTime.now());
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amt == null || amt <= 0) {
      setState(() => _error = tr('Enter an amount above zero'));
      return;
    }
    await widget.store.saveTx(BankTx(kind: widget.kind, amount: amt, date: _date, note: _note.text.trim()));
    if (mounted) Navigator.pop(context, widget.kind == TxKind.deposit ? tr('Deposit added') : tr('Withdrawal added'));
  }

  @override
  Widget build(BuildContext context) {
    final deposit = widget.kind == TxKind.deposit;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(deposit ? tr('Add deposit') : tr('Add withdrawal'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Amount ({currency})', {'currency': widget.store.settings.currency}), errorText: _error),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2000), lastDate: DateTime.now());
            if (d != null) setState(() => _date = isoDate(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: tr('Date'), suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(Fmt.date(_date)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: InputDecoration(labelText: tr('Note (optional), e.g. bookmaker'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: Text(tr('Save'))),
      ]),
    );
  }
}

/// List of deposits and withdrawals, with swipe to delete.
class TransactionsPage extends StatelessWidget {
  const TransactionsPage({super.key, required this.store});
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final fmt = Fmt(store.settings);
        final s = store.stats;
        return Scaffold(
          appBar: AppBar(title: Text(tr('Deposits and withdrawals'))),
          body: ListView(children: [
            ListTile(
              title: Text(tr('Starting bankroll')),
              subtitle: Text(tr('from {date}', {'date': Fmt.date(store.settings.startDate)})),
              trailing: Text(fmt.money(store.settings.startBankroll)),
            ),
            ListTile(title: Text(tr('Deposits')), trailing: Text(fmt.money(s.deposits))),
            ListTile(title: Text(tr('Withdrawals')), trailing: Text(fmt.money(s.withdrawals))),
            ListTile(
              title: Text(tr('Betting profit / loss')),
              trailing: Text(fmt.money(s.profit, sign: true), style: TextStyle(color: BankColors.forValue(context, s.profit))),
            ),
            ListTile(
              title: Text(tr('Current bankroll'), style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(fmt.money(s.balance), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(),
            if (store.txs.isEmpty)
              Padding(padding: EdgeInsets.all(24), child: Center(child: Text(tr('No deposits or withdrawals yet.')))),
            for (final t in store.txs)
              Dismissible(
                key: ValueKey('tx${t.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: BankColors.loss(context),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) => store.deleteTx(t),
                child: ListTile(
                  leading: Icon(t.kind == TxKind.deposit ? Icons.south_west : Icons.north_east),
                  title: Text(t.kind == TxKind.deposit ? tr('Deposit') : tr('Withdrawal')),
                  subtitle: Text([Fmt.date(t.date), if (t.note.isNotEmpty) t.note].join(' · ')),
                  trailing: Text(
                    '${t.kind == TxKind.deposit ? '+' : '−'}${fmt.money(t.amount)}',
                    style: TextStyle(color: t.kind == TxKind.deposit ? BankColors.win(context) : null),
                  ),
                ),
              ),
          ]),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showTxSheet(context, store, TxKind.withdrawal),
                    icon: const Icon(Icons.remove),
                    label: Text(tr('Withdrawal')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showTxSheet(context, store, TxKind.deposit),
                    icon: const Icon(Icons.add),
                    label: Text(tr('Deposit')),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Starting bankroll, unit size, currency and odds format.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final BankStore store;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _start, _unit;
  final _aiKey = TextEditingController();
  late final _name = TextEditingController(text: widget.store.profileName);
  late String _currency, _startDate;
  late OddsFormat _odds;
  bool _showKey = false;
  bool _alerts = true;

  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    _start = TextEditingController(text: s.startBankroll.toString());
    _unit = TextEditingController(text: s.unit.toString());
    _currency = currencies.contains(s.currency) ? s.currency : 'USD';
    _startDate = s.startDate;
    _odds = s.oddsFormat;
    widget.store.pref(aiKeyPref).then((k) {
      if (mounted && k != null) _aiKey.text = k;
    });
    widget.store.pref(alertsEnabledPref).then((v) {
      if (mounted) setState(() => _alerts = v != '0');
    });
  }

  /// Applies straight away, like the theme.
  Future<void> _setAlerts(bool on) async {
    setState(() => _alerts = on);
    final push = PushAlerts.instance;
    // Asked for before anything else: Safari only shows the prompt for a tap.
    final asked = !on
        ? null
        : push.available
            ? push.enable(widget.store)
            : NotificationSink().requestPermission();
    await widget.store.setPref(alertsEnabledPref, on ? '1' : '0');
    if (asked != null) await asked;
    if (!on && push.available) await push.disable(widget.store);
  }

  @override
  void dispose() {
    _start.dispose();
    _unit.dispose();
    _aiKey.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = widget.store.settings.copyWith(
      startBankroll: double.tryParse(_start.text.replaceAll(',', '.')) ?? 0,
      unit: double.tryParse(_unit.text.replaceAll(',', '.')) ?? 0,
      currency: _currency,
      startDate: _startDate,
      oddsFormat: _odds,
    );
    await widget.store.setPref(aiKeyPref, _aiKey.text.trim());
    await widget.store.setProfileName(_name.text);
    await widget.store.saveSettings(s);
    if (mounted) Navigator.pop(context, tr('Settings saved'));
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Profile'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(children: [
          InkWell(
            key: const Key('avatar-button'),
            customBorder: const CircleBorder(),
            onTap: () => showAvatarPicker(context, widget.store),
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => ProfileAvatar(store: widget.store, size: 64),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Your name')),
              ),
              TextButton(
                onPressed: () => showAvatarPicker(context, widget.store),
                child: Text(tr('Change avatar')),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 24),
        Text(tr('Language'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppLanguage>(
              key: const Key('language'),
              showSelectedIcon: false,
              segments: [
                for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label)),
              ],
              selected: {widget.store.language},
              onSelectionChanged: (v) => widget.store.setLanguage(v.first),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(tr('Theme'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => ThemePicker(
            selected: widget.store.themeId,
            onSelected: widget.store.setTheme,
          ),
        ),
        const SizedBox(height: 24),
        Text(tr('Bankroll'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        TextField(
          controller: _start,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Starting bankroll')),
        ),
        gap,
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_startDate) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now());
            if (d != null) setState(() => _startDate = isoDate(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: tr('Start date'), suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(Fmt.date(_startDate)),
          ),
        ),
        gap,
        TextField(
          controller: _unit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: tr('Unit size'), helperText: tr('The stake you treat as one unit, used to show profit in units')),
        ),
        gap,
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: InputDecoration(labelText: tr('Currency')),
          items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        ),
        gap,
        DropdownButtonFormField<OddsFormat>(
          initialValue: _odds,
          decoration: InputDecoration(labelText: tr('Odds format')),
          items: [
            DropdownMenuItem(value: OddsFormat.decimal, child: Text(tr('Decimal (2.50)'))),
            DropdownMenuItem(value: OddsFormat.american, child: Text(tr('American (+150)'))),
          ],
          onChanged: (v) => setState(() => _odds = v ?? _odds),
        ),
        const SizedBox(height: 24),
        Text(tr('Live alerts'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        SwitchListTile(
          key: const Key('alerts-switch'),
          contentPadding: EdgeInsets.zero,
          value: _alerts,
          onChanged: _setAlerts,
          title: Text(tr('Alerts for matches in open bets')),
          subtitle: Text(PushAlerts.instance.available
              ? tr('Kick-off, every goal and the final score for matches in your pending bets and open parlays, also with BetPilot closed. On iPhone, open BetPilot from its Home Screen icon to turn them on.')
              : tr('Kick-off, every goal and the final score for matches in your pending bets and open parlays. Checked every minute while BetPilot is open or running in the background.')),
        ),
        // Alerts are on from the start, but the browser only asks for a tap.
        if (_alerts && PushAlerts.instance.available && !PushAlerts.instance.channel.permitted)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              key: const Key('alerts-allow'),
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(tr('Allow notifications')),
              onPressed: () async {
                final ok = await PushAlerts.instance.enable(widget.store);
                if (mounted) setState(() {});
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('Notifications are blocked. Allow them for BetPilot in the iPhone Settings app, under Notifications.'))));
                }
              },
            ),
          ),
        const SizedBox(height: 24),
        Text(tr('AI chat'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          tr('Optional. With an Anthropic API key the Matchboard chat can answer any question, searching the web for news, injuries and anything else. Questions are sent to Anthropic and billed to your own account (console.anthropic.com). Without a key the chat answers from the match data only.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('ai-key'),
          controller: _aiKey,
          obscureText: !_showKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: tr('Anthropic API key'),
            hintText: 'sk-ant-…',
            suffixIcon: IconButton(
              tooltip: _showKey ? tr('Hide') : tr('Show'),
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Text(tr('Save settings'))),
      ]),
    );
  }
}

/// Two-by-two grid of theme cards; the choice applies straight away.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.25,
      children: [for (final t in appThemes) _ThemeCard(theme: t, selected: t.id == selected, onTap: () => onSelected(t.id))],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.selected, required this.onTap});
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final ring = Theme.of(context).colorScheme.primary;
    return Material(
      color: t.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? ring : t.outlineVariant, width: selected ? 2.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: t.hero),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              child: Row(children: [
                for (final c in [t.primary, t.secondary, t.tertiary])
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(t.localName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.onSurface, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              if (selected) Icon(Icons.check_circle, color: t.primary, size: 20),
            ]),
            Text(t.localDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.onSurfaceVariant, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
