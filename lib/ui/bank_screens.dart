import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import 'format.dart';

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
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    await widget.store.saveTx(BankTx(kind: widget.kind, amount: amt, date: _date, note: _note.text.trim()));
    if (mounted) Navigator.pop(context, widget.kind == TxKind.deposit ? 'Deposit added' : 'Withdrawal added');
  }

  @override
  Widget build(BuildContext context) {
    final deposit = widget.kind == TxKind.deposit;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(deposit ? 'Add deposit' : 'Add withdrawal', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount (${widget.store.settings.currency})', errorText: _error),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: DateTime.parse(_date), firstDate: DateTime(2000), lastDate: DateTime.now());
            if (d != null) setState(() => _date = isoDate(d));
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(Fmt.date(_date)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional), e.g. bookmaker')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Save')),
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
          appBar: AppBar(title: const Text('Deposits and withdrawals')),
          body: ListView(children: [
            ListTile(
              title: const Text('Starting bankroll'),
              subtitle: Text('from ${Fmt.date(store.settings.startDate)}'),
              trailing: Text(fmt.money(store.settings.startBankroll)),
            ),
            ListTile(title: const Text('Deposits'), trailing: Text(fmt.money(s.deposits))),
            ListTile(title: const Text('Withdrawals'), trailing: Text(fmt.money(s.withdrawals))),
            ListTile(
              title: const Text('Betting profit / loss'),
              trailing: Text(fmt.money(s.profit, sign: true), style: TextStyle(color: BankColors.forValue(context, s.profit))),
            ),
            ListTile(
              title: const Text('Current bankroll', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(fmt.money(s.balance), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(),
            if (store.txs.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No deposits or withdrawals yet.'))),
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
                  title: Text(t.kind == TxKind.deposit ? 'Deposit' : 'Withdrawal'),
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
                    label: const Text('Withdrawal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => showTxSheet(context, store, TxKind.deposit),
                    icon: const Icon(Icons.add),
                    label: const Text('Deposit'),
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
  late String _currency, _startDate;
  late OddsFormat _odds;

  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    _start = TextEditingController(text: s.startBankroll.toString());
    _unit = TextEditingController(text: s.unit.toString());
    _currency = currencies.contains(s.currency) ? s.currency : 'USD';
    _startDate = s.startDate;
    _odds = s.oddsFormat;
  }

  @override
  void dispose() {
    _start.dispose();
    _unit.dispose();
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
    await widget.store.saveSettings(s);
    if (mounted) Navigator.pop(context, 'Settings saved');
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: const Text('Bankroll settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _start,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Starting bankroll'),
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
            decoration: const InputDecoration(labelText: 'Start date', suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(Fmt.date(_startDate)),
          ),
        ),
        gap,
        TextField(
          controller: _unit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Unit size', helperText: 'The stake you treat as one unit, used to show profit in units'),
        ),
        gap,
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: const InputDecoration(labelText: 'Currency'),
          items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _currency = v ?? _currency),
        ),
        gap,
        DropdownButtonFormField<OddsFormat>(
          initialValue: _odds,
          decoration: const InputDecoration(labelText: 'Odds format'),
          items: const [
            DropdownMenuItem(value: OddsFormat.decimal, child: Text('Decimal (2.50)')),
            DropdownMenuItem(value: OddsFormat.american, child: Text('American (+150)')),
          ],
          onChanged: (v) => setState(() => _odds = v ?? _odds),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Save settings')),
      ]),
    );
  }
}
