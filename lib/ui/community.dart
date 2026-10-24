import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/fixtures.dart';
import '../data/models.dart' show isoDate;
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../logic/community.dart';
import '../logic/pro_tips.dart';
import 'bet_form.dart';
import 'format.dart';
import 'matches_screen.dart' show TeamLogo;
import 'pro_tips_page.dart' show TokenCoin, showTokensSheet;
import 'profile.dart';
import 'stake_builder.dart' show StakeMatchPicker;

Future<void> openCommunity(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today, int tab = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CommunityPage(store: store, api: api, today: today, initialTab: tab),
    ));

/// The community: bets for sale from pro bettors, the pro bettor challenge
/// and the user's social profile, which they make before they can enter.
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, required this.store, required this.api, this.today, this.initialTab = 0});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;
  final int initialTab;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final profile = store.socialProfile;
          if (profile == null) {
            return Scaffold(appBar: AppBar(title: Text(tr('Community'))), body: _CreateProfile(store: store));
          }
          return DefaultTabController(
            length: 3,
            initialIndex: initialTab,
            child: Scaffold(
              appBar: AppBar(
                title: Text(tr('Community')),
                bottom: TabBar(tabs: [
                  Tab(text: tr('Bets for sale')),
                  Tab(text: tr('Pro bettor')),
                  Tab(text: tr('Profile')),
                ]),
              ),
              body: TabBarView(children: [
                _Market(store: store, api: api, today: today),
                _ProBettor(store: store, api: api, today: today),
                _Profile(store: store),
              ]),
            ),
          );
        },
      );
}

/// A line that says the community is a preview on this phone.
class _PreviewNote extends StatelessWidget {
  const _PreviewNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr('Community preview: profiles, sellers and their bets live on this phone and are simulated until the community goes online.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Profile

class _CreateProfile extends StatefulWidget {
  const _CreateProfile({required this.store});
  final BankStore store;

  @override
  State<_CreateProfile> createState() => _CreateProfileState();
}

class _CreateProfileState extends State<_CreateProfile> {
  late final _name = TextEditingController(text: widget.store.profileName);
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  late final _avatar = ValueNotifier(widget.store.avatar.startsWith('person:') ? widget.store.avatar : 'person:0');
  String? _handleError;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _avatar.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final handle = cleanHandle(_handle.text);
    if (handle == null) {
      setState(() => _handleError = tr('3 to 20 letters, digits or _'));
      return;
    }
    final name = _name.text.trim().isEmpty ? handle : _name.text.trim();
    await widget.store.saveSocialProfile(SocialProfile(
      name: name,
      handle: handle,
      bio: _bio.text.trim(),
      avatar: _avatar.value,
      joined: communityClock().toIso8601String(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
      Icon(Icons.groups_2, size: 48, color: cs.primary),
      const SizedBox(height: 10),
      Text(tr('Create your social profile'),
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(
        tr('Everyone in the community has a social profile. It shows on the bets you place in the pro bettor challenge and, once you pass it, on the bets you sell.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      Center(
        child: ValueListenableBuilder(
          valueListenable: _avatar,
          builder: (context, avatar, _) => InkWell(
            key: const Key('community-avatar'),
            customBorder: const CircleBorder(),
            onTap: () => pickAvatar(
              context,
              current: () => _avatar.value,
              listenable: _avatar,
              onPick: (v) async => _avatar.value = v,
              name: () => _name.text,
            ),
            child: Stack(children: [
              AvatarImage(avatar: avatar, name: _name.text, size: 88),
              Positioned(
                right: 0,
                bottom: 0,
                child: CircleAvatar(radius: 14, backgroundColor: cs.primary, child: Icon(Icons.edit, size: 16, color: cs.onPrimary)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('community-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: tr('Name'), border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('community-handle'),
        controller: _handle,
        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[@\s]'))],
        decoration: InputDecoration(
          labelText: tr('Username'),
          prefixText: '@',
          errorText: _handleError,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _handleError = null),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('community-bio'),
        controller: _bio,
        maxLines: 2,
        maxLength: 120,
        decoration: InputDecoration(labelText: tr('About you (optional)'), border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const Key('community-create'),
        onPressed: _create,
        icon: const Icon(Icons.how_to_reg),
        label: Text(tr('Create profile and enter')),
      ),
      const _PreviewNote(),
    ]);
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.store});
  final BankStore store;

  Future<void> _edit(BuildContext context, SocialProfile p) async {
    final bio = TextEditingController(text: p.bio);
    final name = TextEditingController(text: p.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Edit profile')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
          TextField(controller: bio, maxLength: 120, decoration: InputDecoration(labelText: tr('About you (optional)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok == true) {
      await store.saveSocialProfile(p.copyWith(name: name.text.trim().isEmpty ? p.name : name.text.trim(), bio: bio.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = store.socialProfile!;
    final c = store.challenge;
    final status = c.status(communityClock());
    final joined = DateTime.tryParse(p.joined);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 32), children: [
      Center(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => pickAvatar(
            context,
            current: () => store.socialProfile?.avatar ?? '',
            listenable: store,
            onPick: (v) => store.saveSocialProfile(store.socialProfile!.copyWith(avatar: v)),
            name: () => p.name,
          ),
          child: AvatarImage(avatar: p.avatar, name: p.name, size: 96),
        ),
      ),
      const SizedBox(height: 12),
      Text(p.name, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      Text('@${p.handle}', textAlign: TextAlign.center, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
      if (p.bio.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(p.bio, textAlign: TextAlign.center),
      ],
      if (joined != null) ...[
        const SizedBox(height: 4),
        Text(tr('Joined {date}', {'date': DateFormat.yMMMd().format(joined)}),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
      const SizedBox(height: 16),
      Row(children: [
        _Stat(value: status == ChallengeStatus.passed ? tr('Pro') : tr('Member'), label: tr('Level')),
        _Stat(value: '${c.placed}', label: tr('Challenge bets')),
        _Stat(value: c.winRate == null ? '-' : '${(c.winRate! * 100).round()}%', label: tr('Win rate')),
        _Stat(value: '${store.boughtListings.length}', label: tr('Bets bought')),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => _edit(context, p), icon: const Icon(Icons.edit_outlined), label: Text(tr('Edit profile'))),
      const _PreviewNote(),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(children: [
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Text(label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

// ----------------------------------------------------------------- Market

class _Market extends StatefulWidget {
  const _Market({required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  State<_Market> createState() => _MarketState();
}

class _MarketState extends State<_Market> with AutomaticKeepAliveClientMixin {
  List<Listing>? _listings;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _listings = null;
      _error = null;
    });
    final day = widget.today ?? communityClock();
    try {
      final matches = await widget.api.featuredMatches(day, max: 8);
      if (mounted) setState(() => _listings = demoListings(matches, day: isoDate(day)));
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _buy(Listing l) async {
    final store = widget.store;
    if (store.tokens < l.price) {
      await showTokensSheet(context, store, need: l.price);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Buy this bet?')),
        content: Text(trn(l.price, '{n} token goes to @{seller} and the bet is yours to see.', '{n} tokens go to @{seller} and the bet is yours to see.',
            {'seller': l.seller.handle})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Buy'))),
        ],
      ),
    );
    if (ok == true) await store.buyListing(l);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = widget.store;
    final cs = Theme.of(context).colorScheme;
    final mine = store.myListings.where((l) => l.bet.kickoff.isAfter(communityClock().subtract(const Duration(hours: 3))));
    final bought = store.boughtListings;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const TokenCoin(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(trn(store.tokens, '{n} token', '{n} tokens'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ),
          FilledButton.tonal(onPressed: () => showTokensSheet(context, store), child: Text(tr('Get tokens'))),
        ]),
      ),
      const SizedBox(height: 12),
      Text(tr('Bets from pro bettors who passed the challenge. The pick shows once you buy it.'),
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      if (_listings == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
          ]),
        ),
      if (_listings != null && _listings!.isEmpty && mine.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('No bets for sale right now. Come back closer to the next big matches.'),
              textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      for (final l in [...mine, ...?_listings]) ...[
        ListingCard(
          listing: bought[l.id] ?? l,
          bought: l.mine || bought.containsKey(l.id),
          onBuy: () => _buy(l),
          onLog: () => openBetForm(context, store,
              template: l.bet.toMatch().toBetTemplate(selection: l.bet.leg.pick, odds: l.bet.leg.odds), api: widget.api),
        ),
        const SizedBox(height: 10),
      ],
      const _PreviewNote(),
    ]);
  }
}

/// One bet for sale: the seller and their record, the match, and the pick
/// once bought.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.bought, required this.onBuy, required this.onLog});
  final Listing listing;
  final bool bought;
  final VoidCallback onBuy;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = listing;
    final s = l.seller;
    final b = l.bet;
    return Card(
      key: Key('listing-${l.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AvatarImage(avatar: s.avatar, name: s.name, size: 40, border: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 4),
                  Icon(Icons.verified, size: 16, color: cs.primary),
                ]),
                Text(
                  l.mine
                      ? tr('@{handle} · your bet', {'handle': s.handle})
                      : tr('@{handle} · {w}-{l} · {pct}% won', {'handle': s.handle, 'w': s.wins, 'l': s.losses, 'pct': s.winPercent}),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const TokenCoin(size: 16),
                const SizedBox(width: 4),
                Text('${l.price}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
              ]),
            ),
          ]),
          const Divider(height: 20),
          Row(children: [
            TeamLogo(url: b.homeLogo, name: b.home, size: 20),
            const SizedBox(width: 2),
            TeamLogo(url: b.awayLogo, name: b.away, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.matchTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text('${DateFormat.MMMd().add_Hm().format(b.kickoff.toLocal())} · ${b.leagueName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          if (bought)
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.leg.market.group, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  Text('${trPick(b.leg.pick)} @ ${b.leg.odds.toStringAsFixed(2)}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                ]),
              ),
              if (!l.mine) TextButton.icon(onPressed: onLog, icon: const Icon(Icons.add, size: 18), label: Text(tr('Log bet'))),
            ])
          else
            Row(children: [
              Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr('{market} · pick hidden', {'market': b.leg.market.group}),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              FilledButton(
                key: Key('buy-${l.id}'),
                onPressed: onBuy,
                child: Text(trn(l.price, 'Buy · {n} token', 'Buy · {n} tokens')),
              ),
            ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- Pro bettor

/// The conditions of the pro bettor challenge, as the page lists them.
List<String> get challengeConditions => [
      tr("Bets can't be removed or changed: once a bet is placed, it counts as 1 of the 30."),
      tr('If your win rate after 30 bets is under 60%, you wait a week and start again.'),
      tr('After 10 bets a restart button appears: you can start again any time, but after a restart you wait one week before the new challenge.'),
      tr('Only those who pass the challenge can sell bets in the community for tokens.'),
      tr("Challenge bets need odds of 1.40 or more, on matches that haven't started."),
    ];

/// Asks for a market of [m] at its price; null when the sheet is closed.
Future<TipLeg?> pickMarket(BuildContext context, FixturesApi api, Match m, {double minOdds = 1.01}) async {
  MatchDetails details;
  try {
    details = await api.details(m);
  } catch (_) {
    details = const MatchDetails();
  }
  if (!context.mounted) return null;
  final legs = [for (final c in pricedMarkets(m, details)) c.leg]..sort((a, b) => a.odds.compareTo(b.odds));
  return showModalBottomSheet<TipLeg>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text(m.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(tr('Pick your bet'), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final leg in legs)
            ListTile(
              key: Key('market-${leg.market.name}'),
              contentPadding: EdgeInsets.zero,
              enabled: leg.odds >= minOdds,
              title: Text(trPick(leg.pick), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(leg.market.group),
              trailing: Text(leg.odds.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: leg.odds >= minOdds ? cs.primary : null)),
              onTap: () => Navigator.pop(context, leg),
            ),
        ]),
      );
    },
  );
}

class _ProBettor extends StatefulWidget {
  const _ProBettor({required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  State<_ProBettor> createState() => _ProBettorState();
}

class _ProBettorState extends State<_ProBettor> {
  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _settle();
  }

  /// Settles the challenge bets whose matches have finished.
  Future<void> _settle() async {
    final now = communityClock();
    final open = <String, CommunityBet>{
      for (final b in store.challenge.bets)
        if (!b.settled && b.kickoff.isBefore(now.subtract(const Duration(minutes: 100)))) b.matchId: b,
    };
    for (final b in open.values) {
      try {
        final d = await widget.api.details(b.toMatch());
        if (d.state == MatchState.finished && d.homeScore != null && d.awayScore != null) {
          await store.settleChallenge(b.matchId, d.homeScore!, d.awayScore!);
        }
      } catch (_) {
        // Tried again next time the page opens.
      }
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _accept() async {
    final ok = await _confirm(tr('Accept the challenge?'), challengeConditions.map((c) => '• $c').join('\n\n'), tr('Accept'));
    if (ok) await store.acceptChallenge();
  }

  Future<void> _restart() async {
    final ok = await _confirm(
      tr('Restart the challenge?'),
      tr('Your {n} bets are cleared and you wait one week before you can start again.', {'n': store.challenge.placed}),
      tr('Restart'),
    );
    if (ok) await store.restartChallenge();
  }

  Future<(Match, TipLeg)?> _pickBet({double minOdds = 1.01}) async {
    final m = await Navigator.of(context).push<Match>(MaterialPageRoute(
      builder: (_) => StakeMatchPicker(api: widget.api, today: widget.today),
    ));
    if (m == null || !mounted) return null;
    final leg = await pickMarket(context, widget.api, m, minOdds: minOdds);
    return leg == null ? null : (m, leg);
  }

  Future<void> _place() async {
    final picked = await _pickBet(minOdds: ProChallenge.minOdds);
    if (picked == null || !mounted) return;
    final (m, leg) = picked;
    final bet = CommunityBet.on(m, leg, placed: communityClock().toIso8601String());
    final why = store.challenge.refuse(bet, communityClock());
    if (why != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(why)));
      return;
    }
    final ok = await _confirm(
      tr('Place this bet?'),
      tr("{pick} @ {odds} on {match}. It can't be removed or changed, and counts as bet {n} of 30.",
          {'pick': trPick(leg.pick), 'odds': leg.odds.toStringAsFixed(2), 'match': m.title, 'n': store.challenge.placed + 1}),
      tr('Place bet'),
    );
    if (!ok) return;
    final err = await store.placeChallengeBet(bet);
    if (err != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _sell() async {
    final picked = await _pickBet();
    if (picked == null || !mounted) return;
    final (m, leg) = picked;
    final p = store.socialProfile!;
    final c = store.challenge;
    await store.sellBet(Listing(
      seller: ProSeller(p.handle, p.name, p.avatar, c.wins, c.settled - c.wins),
      bet: CommunityBet.on(m, leg, placed: communityClock().toIso8601String()),
      price: listingPrice(leg.odds),
      mine: true,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Your bet is for sale in Bets for sale.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = store.challenge;
    final now = communityClock();
    final status = c.status(now);
    final rate = c.winRate;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.workspace_premium, color: cs.onPrimary, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(status == ChallengeStatus.passed ? tr("You're a pro bettor") : tr('Become a pro bettor'),
                  style: theme.textTheme.titleLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            tr('Enable the pro bettor challenge: place at least 30 bets with a win rate over 60% to unlock your pro bettor profile and start selling your bets!'),
            style: TextStyle(color: cs.onPrimary),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Conditions'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final line in challengeConditions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline, size: 18, color: cs.primary)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line)),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      if (status != ChallengeStatus.notStarted && status != ChallengeStatus.waiting) ...[
        Row(children: [
          Expanded(
            child: Text(tr('{n} of 30 bets', {'n': c.placed}),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Text(rate == null ? tr('No results yet') : tr('{w} of {s} won · {pct}%', {'w': c.wins, 's': c.settled, 'pct': (rate * 100).round()}),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: rate == null ? cs.onSurfaceVariant : (rate >= ProChallenge.passRate ? BankColors.win(context) : BankColors.loss(context)))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: c.placed / ProChallenge.target, minHeight: 10),
        ),
        const SizedBox(height: 14),
      ],
      switch (status) {
        ChallengeStatus.notStarted => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (c.lastRate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(tr('Your last challenge ended at {pct}%. You can start again now.', {'pct': (c.lastRate! * 100).round()}),
                    textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            FilledButton.icon(
              key: const Key('challenge-accept'),
              onPressed: _accept,
              icon: const Icon(Icons.flag),
              label: Text(tr('Accept the challenge')),
            ),
          ]),
        ChallengeStatus.active => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              key: const Key('challenge-place'),
              onPressed: _place,
              icon: const Icon(Icons.add),
              label: Text(tr('Place a challenge bet')),
            ),
            if (c.canRestart(now)) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('challenge-restart'),
                onPressed: _restart,
                icon: const Icon(Icons.restart_alt),
                label: Text(tr('Restart (wait one week)')),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    trn(ProChallenge.restartAfter - c.placed, 'The restart button appears after {n} more bet.',
                        'The restart button appears after {n} more bets.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
          ]),
        ChallengeStatus.awaitingResults => Text(tr('All 30 bets are placed. The result comes once every match has finished.'),
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ChallengeStatus.waiting => Card(
            margin: EdgeInsets.zero,
            color: cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Icon(Icons.hourglass_top, color: cs.onSurfaceVariant),
                const SizedBox(height: 6),
                Text(
                  c.lastRate == null
                      ? tr('You restarted the challenge.')
                      : tr('Your challenge ended at {pct}%, under the 60% needed.', {'pct': (c.lastRate! * 100).round()}),
                  textAlign: TextAlign.center,
                ),
                Text(tr('You can start again on {date}.', {'date': DateFormat.yMMMd().format(c.waitUntil!)}),
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ChallengeStatus.passed => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('You passed the challenge. Sell your bets to the community for tokens.'), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('challenge-sell'),
              onPressed: _sell,
              icon: const Icon(Icons.sell_outlined),
              label: Text(tr('Sell a bet')),
            ),
          ]),
      },
      if (c.bets.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(tr('Your challenge bets'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final (i, b) in c.bets.indexed.toList().reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: cs.surfaceContainerHighest,
              child: Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            title: Text('${trPick(b.leg.pick)} @ ${b.leg.odds.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(b.matchTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              b.settled ? (b.won ? tr('Won') : tr('Lost')) : tr('Pending'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: !b.settled ? cs.onSurfaceVariant : (b.won ? BankColors.win(context) : BankColors.loss(context)),
              ),
            ),
          ),
      ],
      const _PreviewNote(),
    ]);
  }
}
