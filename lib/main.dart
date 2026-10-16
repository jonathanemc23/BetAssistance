import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/fixtures.dart';
import 'data/models.dart';
import 'data/store.dart';
import 'logic/share.dart';
import 'ui/bank_screens.dart';
import 'ui/bet_form.dart';
import 'ui/bets_screen.dart';
import 'ui/charts_screen.dart';
import 'ui/format.dart';
import 'ui/matches_screen.dart';
import 'ui/share_ui.dart';
import 'ui/summary_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final store = BankStore(db);
  await store.load();
  runApp(BankTrackApp(store: store, links: AppLinks().uriLinkStream));
}

class BankTrackApp extends StatelessWidget {
  const BankTrackApp({super.key, required this.store, this.links, this.fixtures, this.today});
  final BankStore store;
  final FixturesApi? fixtures;
  final DateTime? today;

  /// Incoming bet links (app_links emits the launch link first, then any
  /// link opened while the app is running).
  final Stream<Uri>? links;

  ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: BankColors.accent, brightness: b),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: BankColors.accent, width: 1.5),
      ),
    ),
    cardTheme: const CardThemeData(elevation: 0),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bank Track',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: HomeShell(store: store, links: links, fixtures: fixtures ?? FixturesApi(), today: today),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, required this.fixtures, this.links, this.today});
  final BankStore store;
  final Stream<Uri>? links;
  final FixturesApi fixtures;
  final DateTime? today;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _visited = <int>{0}; // tabs are built on first visit (Matches loads from the network)
  StreamSubscription<Uri>? _linkSub;

  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _linkSub = widget.links?.listen(_openLink);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _openLink(Uri uri) {
    final bet = BetLink.decode(
      uri.toString(),
      today: isoDate(DateTime.now()),
      created: DateTime.now().toIso8601String(),
    );
    if (!mounted) return;
    if (bet == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't read that bet link")));
      return;
    }
    openBetForm(context, store, template: bet);
  }

  Future<void> _pasteLink() async {
    final bet = await showPasteLink(context);
    if (bet != null && mounted) await openBetForm(context, store, template: bet);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            1 => 'Bet register',
            2 => 'Matches',
            3 => 'Charts',
            _ => 'Bank Track',
          }, style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (_tab == 1)
              IconButton(tooltip: 'Open a bet link', icon: const Icon(Icons.add_link), onPressed: _pasteLink),
            IconButton(
              tooltip: 'Bankroll settings',
              icon: const Icon(Icons.tune),
              onPressed: () async {
                final msg = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsPage(store: store)),
                );
                if (msg != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            SummaryScreen(
              store: store,
              onLogBet: () => openBetForm(context, store),
              onOpenBets: () => setState(() => _visited.add(_tab = 1)),
            ),
            BetsScreen(store: store),
            if (_visited.contains(2))
              MatchesScreen(store: store, api: widget.fixtures, today: widget.today)
            else
              const SizedBox(),
            ChartsScreen(store: store),
          ],
        ),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => openBetForm(context, store),
                icon: const Icon(Icons.add),
                label: const Text('Log bet'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _visited.add(_tab = i)),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Summary',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Bets',
            ),
            NavigationDestination(
              icon: Icon(Icons.sports_soccer_outlined),
              selectedIcon: Icon(Icons.sports_soccer),
              label: 'Matches',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Charts',
            ),
          ],
        ),
      ),
    );
  }
}
