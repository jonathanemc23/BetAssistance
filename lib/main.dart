import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/account.dart';
import 'data/bet_settler.dart';
import 'data/database.dart';
import 'l10n/l10n.dart';
import 'data/fixtures.dart';
import 'data/live_alert_service.dart';
import 'data/models.dart';
import 'data/push_alerts.dart';
import 'data/store.dart';
import 'data/sync.dart';
import 'logic/share.dart';
import 'ui/account_screens.dart';
import 'ui/bank_screens.dart';
import 'ui/bet_form.dart';
import 'ui/bets_screen.dart';
import 'ui/charts_screen.dart';
import 'ui/community.dart';
import 'ui/home_screen.dart';
import 'ui/matches_screen.dart';
import 'ui/themes.dart';
import 'ui/share_ui.dart';
import 'ui/slip_import.dart';
import 'ui/tools_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // In the browser the database is SQLite in WebAssembly, kept in IndexedDB.
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  final db = await AppDatabase.open();
  final store = BankStore(db);
  await store.load();
  final fixtures = FixturesApi();
  // Accounts: the data is saved on the user's account when signed in.
  final account = AccountService(store: store);
  SyncService? sync;
  if (account.configured) {
    await account.restore();
    sync = SyncService(store: store, account: account)..start();
  }
  LiveAlertService(
    store: store,
    api: fixtures,
    sink: NotificationSink(),
    settler: BetSettler(store: store, api: fixtures),
    push: kIsWeb ? PushAlerts.instance : null,
  ).start();
  runApp(BankTrackApp(
    store: store,
    fixtures: fixtures,
    links: AppLinks().uriLinkStream.where(_isBetLink),
    account: sync == null ? null : account,
    sync: sync,
  ));
}

/// On the web every launch reports the page address as a link; only
/// `?d=<code>` (from the share page) is a bet.
bool _isBetLink(Uri uri) => !kIsWeb || uri.queryParameters.containsKey('d');

class BankTrackApp extends StatelessWidget {
  const BankTrackApp({super.key, required this.store, this.links, this.fixtures, this.today, this.account, this.sync});
  final BankStore store;

  /// Accounts, when set up for this build (see [AccountService.configured]).
  final AccountService? account;
  final SyncService? sync;
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
        child: HomeShell(
            store: store, links: links, fixtures: fixtures ?? FixturesApi(), today: today, account: account, sync: sync),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell(
      {super.key, required this.store, required this.fixtures, this.links, this.today, this.account, this.sync});
  final BankStore store;
  final AccountService? account;
  final SyncService? sync;
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
  AppLifecycleListener? _lifecycle;
  bool _choiceShown = false;

  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _linkSub = widget.links?.listen(_openLink);
    final sync = widget.sync;
    if (sync != null) {
      sync.addListener(_syncChanged);
      _lifecycle = AppLifecycleListener(onResume: sync.sync);
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerSignIn());
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    widget.sync?.removeListener(_syncChanged);
    _lifecycle?.dispose();
    super.dispose();
  }

  /// The sign-in page at launch, until the user signs in or says not now.
  Future<void> _offerSignIn() async {
    final account = widget.account;
    if (account == null || account.signedIn || !mounted) return;
    if (await store.pref(accountSkippedPref) == '1' || !mounted) return;
    await Navigator.push<bool>(
        context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => LoginPage(account: account, atLaunch: true)));
  }

  /// Asks which data to keep when this device and the account disagree.
  void _syncChanged() {
    final sync = widget.sync!;
    if (sync.state != SyncState.needsChoice) {
      _choiceShown = false;
      return;
    }
    if (_choiceShown || !mounted) return;
    _choiceShown = true;
    showSyncChoice(context, sync);
  }

  void _openAccount() {
    final account = widget.account!;
    _push((_) => account.signedIn ? AccountPage(account: account, sync: widget.sync!) : LoginPage(account: account));
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

    final account = widget.account;
    final actions = <VoidCallback>[
      _openTools,
      () => openCommunity(context, store: store, api: widget.fixtures, today: widget.today),
      if (account != null) _openAccount,
      _openSettings,
    ];
    // Long names (and long translations) end in an ellipsis, not an overflow.
    Widget label(String text, {Key? key, TextStyle? style}) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(text, key: key, style: style, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
        );
    return NavigationDrawer(
      selectedIndex: null,
      onDestinationSelected: (i) => go(actions[i]),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: const BrandTitle(size: 36),
        ),
        NavigationDrawerDestination(
            icon: Icon(Icons.handyman_outlined), label: label(tr('Bet Tools'), key: const Key('drawer-tools'))),
        NavigationDrawerDestination(
            icon: Icon(Icons.groups_2_outlined), label: label(tr('Community'), key: const Key('drawer-community'))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8), child: Divider()),
        if (account != null)
          NavigationDrawerDestination(
            icon: Icon(account.signedIn ? Icons.cloud_done_outlined : Icons.account_circle_outlined),
            label: label(account.signedIn ? (account.account!.email.isEmpty ? tr('Account') : account.account!.email) : tr('Sign in'),
                key: const Key('drawer-account')),
          ),
        NavigationDrawerDestination(icon: Icon(Icons.tune), label: label(tr('Settings'))),
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
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                FloatingActionButton.extended(
                  heroTag: 'bet-slip',
                  onPressed: () => importBetFromSlip(context, store: store, api: widget.fixtures),
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(tr('From screenshot')),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'log-bet',
                  onPressed: () => openBetForm(context, store, api: widget.fixtures),
                  icon: const Icon(Icons.add),
                  label: Text(tr('Log bet')),
                ),
              ])
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
