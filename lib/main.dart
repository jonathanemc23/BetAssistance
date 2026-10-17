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
import 'ui/matchboard_screen.dart';
import 'ui/matches_screen.dart';
import 'ui/parlay_screens.dart';
import 'ui/themes.dart';
import 'ui/share_ui.dart';
import 'ui/summary_screen.dart';
import 'ui/tools_screen.dart';

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

  /// The theme for a [appThemes] id, as the app builds it.
  static ThemeData theme(String id) => themeById(id).data();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        // Rebuilds only when the store notifies; the theme comes from it.
        listenable: store,
        builder: (context, child) => MaterialApp(
          title: 'Bank Track',
          debugShowCheckedModeBanner: false,
          theme: theme(store.themeId),
          home: child,
        ),
        child: HomeShell(store: store, links: links, fixtures: fixtures ?? FixturesApi(), today: today),
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
    final bet = BetLink.decode(uri.toString(), today: isoDate(DateTime.now()), created: DateTime.now().toIso8601String());
    if (!mounted) return;
    if (bet == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't read that bet link")));
      return;
    }
    openBetForm(context, store, template: bet);
  }

  void _push(Widget Function(BuildContext) page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: page));

  void _openMatches() => _push((_) => Scaffold(
        appBar: AppBar(title: const Text('Matches')),
        body: MatchesScreen(store: store, api: widget.fixtures, today: widget.today),
      ));

  Future<void> _openSettings() async {
    final msg = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => SettingsPage(store: store)));
    if (msg != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _drawer(BuildContext context) {
    final theme = Theme.of(context);
    void go(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    return NavigationDrawer(
      selectedIndex: null,
      onDestinationSelected: (i) => go(switch (i) {
        0 => _openMatches,
        1 => () => _push((_) => Scaffold(
              appBar: AppBar(title: const Text('Matchboard')),
              body: MatchboardScreen(store: store, api: widget.fixtures, onBrowseMatches: _openMatches),
            )),
        2 => () => _push((_) => ParlaysPage(store: store, api: widget.fixtures)),
        _ => _openSettings,
      }),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Text('Bank Track', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        const NavigationDrawerDestination(
            icon: Icon(Icons.sports_soccer_outlined), label: Text('Matches')),
        const NavigationDrawerDestination(
            icon: Icon(Icons.space_dashboard_outlined), label: Text('Matchboard')),
        const NavigationDrawerDestination(
            icon: Icon(Icons.account_tree_outlined), label: Text('Parlay builder')),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
        const NavigationDrawerDestination(icon: Icon(Icons.tune), label: Text('Settings')),
      ],
    );
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
        drawer: _drawer(context),
        appBar: AppBar(
          title: Text(switch (_tab) { 1 => 'Bet register', 2 => 'Bet Tools', 3 => 'Charts', _ => 'Bank Track' },
              style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (_tab == 1)
              IconButton(tooltip: 'Open a bet link', icon: const Icon(Icons.add_link), onPressed: _pasteLink),
            IconButton(tooltip: 'Settings', icon: const Icon(Icons.tune), onPressed: _openSettings),
          ],
        ),
        body: IndexedStack(index: _tab, children: [
          SummaryScreen(
            store: store,
            onLogBet: () => openBetForm(context, store),
            onOpenBets: () => setState(() => _tab = 1),
          ),
          BetsScreen(store: store),
          BetToolsScreen(store: store, api: widget.fixtures, onOpenMatches: _openMatches),
          ChartsScreen(store: store),
        ]),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => openBetForm(context, store),
                icon: const Icon(Icons.add),
                label: const Text('Log bet'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Summary'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bets'),
            NavigationDestination(
                icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: 'Bet Tools'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Charts'),
          ],
        ),
      ),
    );
  }
}
