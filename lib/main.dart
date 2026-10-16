import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/store.dart';
import 'ui/bank_screens.dart';
import 'ui/bets_screen.dart';
import 'ui/charts_screen.dart';
import 'ui/format.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final store = BankStore(db);
  await store.load();
  runApp(BankTrackApp(store: store));
}

class BankTrackApp extends StatelessWidget {
  const BankTrackApp({super.key, required this.store});
  final BankStore store;

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: BankColors.accent, brightness: b),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardThemeData(elevation: 0),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bank Track',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: HomeShell(store: store),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final BankStore store;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _betsKey = GlobalKey<BetsScreenState>();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Bank Track', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Bankroll settings',
              icon: const Icon(Icons.tune),
              onPressed: () async {
                final msg = await Navigator.push<String>(
                    context, MaterialPageRoute(builder: (_) => SettingsPage(store: store)));
                if (msg != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
            ),
          ],
        ),
        body: IndexedStack(index: _tab, children: [
          BetsScreen(key: _betsKey, store: store),
          ChartsScreen(store: store),
        ]),
        floatingActionButton: _tab == 0
            ? FloatingActionButton.extended(
                onPressed: () => _betsKey.currentState?.openBet(),
                icon: const Icon(Icons.add),
                label: const Text('Log bet'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Bets'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Charts'),
          ],
        ),
      ),
    );
  }
}
