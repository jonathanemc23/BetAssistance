import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/database.dart';
import 'l10n/l10n.dart';
import 'data/fixtures.dart';
import 'data/live_alert_service.dart';
import 'data/models.dart';
import 'data/store.dart';
import 'logic/share.dart';
import 'ui/bank_screens.dart';
import 'ui/bet_form.dart';
import 'ui/bets_screen.dart';
import 'ui/charts_screen.dart';
import 'ui/home_screen.dart';
import 'ui/matches_screen.dart';
import 'ui/themes.dart';
import 'ui/share_ui.dart';
import 'ui/tools_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final store = BankStore(db);
  await store.load();
  final fixtures = FixturesApi();
  LiveAlertService(store: store, api: fixtures, sink: NotificationSink()).start();
  runApp(BankTrackApp(store: store, fixtures: fixtures, links: AppLinks().uriLinkStream));
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
          title: 'BetPilot',
          debugShowCheckedModeBanner: false,
          theme: theme(store.themeId),
          locale: store.language.locale,
          supportedLocales: [for (final l in AppLanguage.values) l.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
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

  /// Matches loads the first time its tab is opened, then stays loaded.
  bool _matchesShown = false;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr("Couldn't read that bet link"))));
      return;
    }
    openBetForm(context, store, template: bet, api: widget.fixtures);
  }

  void _push(Widget Function(BuildContext) page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: page));

  /// Matches is a bottom tab; pages opened on top close to show it.
  void _openMatches() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _tab = 2);
    _matchesShown = true;
  }

  void _openTools() => _push((_) => Scaffold(
        appBar: AppBar(title: Text(tr('Bet Tools'))),
        body: BetToolsScreen(store: store, api: widget.fixtures, today: widget.today),
      ));

  Future<void> _openSettings() async {
    final msg = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => SettingsPage(store: store)));
    if (msg != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _drawer(BuildContext context) {
    void go(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    return NavigationDrawer(
      selectedIndex: null,
      onDestinationSelected: (i) => go(i == 0 ? _openTools : _openSettings),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: const BrandTitle(size: 36),
        ),
        NavigationDrawerDestination(icon: Icon(Icons.handyman_outlined), label: Text(tr('Bet Tools'))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
        NavigationDrawerDestination(icon: Icon(Icons.tune), label: Text(tr('Settings'))),
      ],
    );
  }

  Future<void> _pasteLink() async {
    final bet = await showPasteLink(context);
    if (bet != null && mounted) await openBetForm(context, store, template: bet, api: widget.fixtures);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        drawer: _drawer(context),
        appBar: AppBar(
          title: _tab == 0
              ? const BrandTitle()
              : Text(switch (_tab) { 1 => tr('Bet register'), 2 => tr('Matches'), _ => tr('Charts') },
                  style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            if (_tab == 1)
              IconButton(tooltip: tr('Open a bet link'), icon: const Icon(Icons.add_link), onPressed: _pasteLink),
            IconButton(tooltip: tr('Settings'), icon: const Icon(Icons.tune), onPressed: _openSettings),
          ],
        ),
        body: IndexedStack(index: _tab, children: [
          HomeScreen(
            store: store,
            api: widget.fixtures,
            today: widget.today,
            onLogBet: () => openBetForm(context, store, api: widget.fixtures),
            onOpenBets: () => setState(() => _tab = 1),
            onOpenMatches: _openMatches,
          ),
          BetsScreen(store: store, api: widget.fixtures),
          if (_tab == 2 || _matchesShown)
            MatchesTabs(store: store, api: widget.fixtures, today: widget.today)
          else
            const SizedBox.shrink(),
          ChartsScreen(store: store),
        ]),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => openBetForm(context, store, api: widget.fixtures),
                icon: const Icon(Icons.add),
                label: Text(tr('Log bet')),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() {
            _tab = i;
            if (i == 2) _matchesShown = true;
          }),
          destinations: [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: tr('Home')),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: tr('Bets')),
            NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined), selectedIcon: Icon(Icons.sports_soccer), label: tr('Matches')),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: tr('Charts')),
          ],
        ),
      ),
    );
  }
}

/// The app's icon and name, as shown in the header and the side menu.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset('assets/brand/icon.png', width: size, height: size),
        ),
        SizedBox(width: size * 0.35),
        Text('BetPilot', style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.72, letterSpacing: 0.2)),
      ]);
}
