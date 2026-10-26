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

Future<void> openCommunity(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPage(store: store, api: api, today: today),
      ),
    );

/// The pro bettor challenge on its own page: what it asks and where the user stands.
Future<void> openProBettor(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('Pro bettor challenge'))),
          body: ListenableBuilder(
            listenable: store,
            builder: (_, _) => _ProBettor(store: store, api: api, today: today),
          ),
        ),
      ),
    );

/// The community: the hottest bets for sale and free bets from other bettors,
/// behind the social profile the user makes before they can enter.
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key, required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final profile = store.socialProfile;
      if (profile == null) {
        return Scaffold(
          appBar: AppBar(title: Text(tr('Join the community'))),
          body: _CreateProfile(store: store),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(tr('Community')),
          actions: [
            IconButton(
              key: const Key('community-profile'),
              tooltip: tr('Your profile'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(tr('Your profile'))),
                    body: ListenableBuilder(
                      listenable: store,
                      builder: (_, _) => _Profile(store: store),
                    ),
                  ),
                ),
              ),
              icon: AvatarImage(avatar: profile.avatar, name: profile.name, size: 32, border: false),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _CommunityHome(store: store, api: api, today: today),
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
      Text(tr('Create your community profile'),
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(
        tr('You need a community profile to join. It shows on the free bets you post, on your pro bettor challenge and, once you pass it, on the bets you sell.'),
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
        label: Text(tr('Create profile and join')),
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
    final freeSettled = [for (final l in store.myFreeBets) if (l.bet.settled) l];
    final freeWon = freeSettled.where((l) => l.bet.won).length;
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
        _Stat(value: '0', label: tr('Followers')),
        _Stat(value: '${store.following.length}', label: tr('Following')),
        _Stat(value: '${store.boughtListings.length}', label: tr('Bets bought')),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _Stat(value: '${store.myFreeBets.length}', label: tr('Free bets')),
        _Stat(value: freeSettled.isEmpty ? '-' : '${freeWon * 100 ~/ freeSettled.length}%', label: tr('Free bets won')),
        _Stat(value: '${c.placed}', label: tr('Challenge bets')),
        _Stat(value: c.winRate == null ? '-' : '${(c.winRate! * 100).round()}%', label: tr('Win rate')),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => _edit(context, p), icon: const Icon(Icons.edit_outlined), label: Text(tr('Edit profile'))),
      if (store.myFreeBets.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(tr('Your free bets'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        for (final l in store.myFreeBets.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${trPick(l.bet.leg.pick)} @ ${l.bet.leg.odds.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(l.bet.matchTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              l.bet.settled ? (l.bet.won ? tr('Won') : tr('Lost')) : tr('Pending'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: !l.bet.settled ? cs.onSurfaceVariant : (l.bet.won ? BankColors.win(context) : BankColors.loss(context)),
              ),
            ),
          ),
      ],
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

/// Spends tokens on [l] after asking, or offers tokens when there aren't enough.
Future<void> _buy(BuildContext context, BankStore store, Listing l) async {
  if (store.tokens < l.price) {
    await showTokensSheet(context, store, need: l.price);
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Buy this bet?')),
      content: Text(
        trn(
          l.price,
          '{n} token goes to @{seller} and the bet is yours to see.',
          '{n} tokens go to @{seller} and the bet is yours to see.',
          {'seller': l.seller.handle},
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Buy'))),
      ],
    ),
  );
  if (ok == true) await store.buyListing(l);
}

void _log(BuildContext context, BankStore store, FixturesApi api, Listing l) => openBetForm(
  context,
  store,
  template: l.bet.toMatch().toBetTemplate(selection: l.bet.leg.pick, odds: l.bet.leg.odds),
  api: api,
);

/// A bet for sale as [ListingCard] shows it, bought or not.
Widget _listingCard(BuildContext context, BankStore store, FixturesApi api, Listing l, {bool hot = false}) {
  final bought = store.boughtListings;
  return ListingCard(
    listing: bought[l.id] ?? l,
    bought: l.mine || bought.containsKey(l.id),
    hot: hot,
    onBuy: () => _buy(context, store, l),
    onLog: () => _log(context, store, api, l),
  );
}

/// The user's own bets for sale that are still worth showing.
Iterable<Listing> _myOpenListings(BankStore store) =>
    store.myListings.where((l) => l.bet.kickoff.isAfter(communityClock().subtract(const Duration(hours: 3))));

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, required this.text, this.color});
  final IconData icon;
  final String title, text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color ?? cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The button at the top of the community that opens the pro bettor challenge.
class _ProBanner extends StatelessWidget {
  const _ProBanner({required this.store, required this.onOpen});
  final BankStore store;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = store.challenge;
    final status = c.status(communityClock());
    final line = switch (status) {
      ChallengeStatus.passed => tr('You passed the challenge: sell your bets for tokens.'),
      ChallengeStatus.active || ChallengeStatus.awaitingResults => tr('Challenge on: {n} of 30 bets placed.', {'n': c.placed}),
      _ => tr('30 bets, 60% won, odds over 1.60. Pass it and sell your bets for tokens.'),
    };
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.workspace_premium, color: cs.onPrimary, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('community-pro-bettor'),
                  style: FilledButton.styleFrom(backgroundColor: cs.onPrimary, foregroundColor: cs.primary),
                  onPressed: onOpen,
                  icon: const Icon(Icons.workspace_premium),
                  label: Text(status == ChallengeStatus.passed ? tr("You're a pro bettor") : tr('Become a pro bettor')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The community's front page: the pro bettor button, the hottest bets to
/// buy and the free bets bettors post to gain followers.
class _CommunityHome extends StatefulWidget {
  const _CommunityHome({required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  State<_CommunityHome> createState() => _CommunityHomeState();
}

class _CommunityHomeState extends State<_CommunityHome> {
  List<Listing>? _listings;
  List<Listing>? _free;
  String? _error;

  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
    _settleFreeBets();
  }

  Future<void> _load() async {
    setState(() {
      _listings = null;
      _free = null;
      _error = null;
    });
    final day = widget.today ?? communityClock();
    try {
      final matches = await widget.api.featuredMatches(day, max: 8);
      if (mounted) {
        setState(() {
          _listings = demoListings(matches, day: isoDate(day));
          _free = demoFreeBets(matches, day: isoDate(day));
        });
      }
    } on FixturesException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Settles the user's free bets whose matches have finished.
  Future<void> _settleFreeBets() async {
    final now = communityClock();
    final open = <String, CommunityBet>{
      for (final l in store.myFreeBets)
        if (!l.bet.settled && l.bet.kickoff.isBefore(now.subtract(const Duration(minutes: 100)))) l.bet.matchId: l.bet,
    };
    for (final b in open.values) {
      try {
        final d = await widget.api.details(b.toMatch());
        if (d.state == MatchState.finished && d.homeScore != null && d.awayScore != null) {
          await store.settleFreeBets(b.matchId, d.homeScore!, d.awayScore!);
        }
      } catch (_) {
        // Tried again next time the page opens.
      }
    }
  }

  Future<void> _postFree() async {
    final picked = await pickCommunityBet(context, widget.api, today: widget.today);
    if (picked == null || !mounted) return;
    final (m, leg) = picked;
    final p = store.socialProfile!;
    final record = store.myFreeBets.where((l) => l.bet.settled);
    final err = await store.postFreeBet(
      Listing(
        seller: ProSeller(
          p.handle,
          p.name,
          p.avatar,
          record.where((l) => l.bet.won).length,
          record.where((l) => !l.bet.won).length,
          pro: store.challenge.status(communityClock()) == ChallengeStatus.passed,
        ),
        bet: CommunityBet.on(m, leg, placed: communityClock().toIso8601String()),
        price: 0,
        mine: true,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? tr('Your free bet is posted for your followers.'))));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final listings = [..._myOpenListings(store), ...?_listings];
    final hot = hottest(listings);
    final now = communityClock();
    final myFree = store.myFreeBets.reversed.where((l) => l.bet.kickoff.isAfter(now.subtract(const Duration(days: 2))));
    // Bought bets whose match has started: they're off the list for sale.
    final played = [
      for (final l in store.boughtListings.values)
        if (l.bet.kickoff.isBefore(now) && l.bet.kickoff.isAfter(now.subtract(const Duration(days: 3)))) l,
    ]..sort((a, b) => b.bet.kickoff.compareTo(a.bet.kickoff));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ProBanner(
            store: store,
            onOpen: () => openProBettor(context, store: store, api: widget.api, today: widget.today),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                const TokenCoin(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trn(store.tokens, '{n} token', '{n} tokens'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(onPressed: () => showTokensSheet(context, store), child: Text(tr('Get tokens'))),
              ],
            ),
          ),
          if (played.isNotEmpty) ...[
            _SectionTitle(
              icon: Icons.receipt_long,
              title: tr('Bets you bought'),
              text: tr('Their result comes in on its own once the match is over.'),
            ),
            for (final l in played) ...[_listingCard(context, store, widget.api, l), const SizedBox(height: 10)],
          ],
          _SectionTitle(
            icon: Icons.local_fire_department,
            color: Colors.deepOrange,
            title: tr('Hottest bets to buy'),
            text: tr('The bets from pro bettors that sell the most today. The pick shows once you buy it.'),
          ),
          if (_listings == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
                ],
              ),
            ),
          if (_listings != null && hot.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('No bets for sale right now. Come back closer to the next big matches.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (final l in hot) ...[_listingCard(context, store, widget.api, l, hot: true), const SizedBox(height: 10)],
          if (_listings != null && listings.length > hot.length)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('community-all-bets'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _AllBetsPage(store: store, api: widget.api, listings: listings),
                  ),
                ),
                icon: const Icon(Icons.storefront_outlined),
                label: Text(tr('See all {n} bets for sale', {'n': listings.length})),
              ),
            ),
          _SectionTitle(
            icon: Icons.card_giftcard,
            title: tr('Free bets'),
            text: tr('Bettors post free bets to gain followers. Follow the ones you like, or post your own.'),
          ),
          OutlinedButton.icon(
            key: const Key('community-post-free'),
            onPressed: _postFree,
            icon: const Icon(Icons.add),
            label: Text(tr('Post a free bet')),
          ),
          const SizedBox(height: 10),
          for (final l in [...myFree, ...?_free]) ...[
            FreeBetCard(
              listing: l,
              following: store.following.contains(l.seller.handle),
              onFollow: () => store.toggleFollow(l.seller.handle),
              onLog: () => _log(context, store, widget.api, l),
            ),
            const SizedBox(height: 10),
          ],
          const _PreviewNote(),
        ],
      ),
    );
  }
}

/// Every bet for sale today, hottest first.
class _AllBetsPage extends StatelessWidget {
  const _AllBetsPage({required this.store, required this.api, required this.listings});
  final BankStore store;
  final FixturesApi api;
  final List<Listing> listings;

  @override
  Widget build(BuildContext context) {
    final sorted = [...listings]..sort((a, b) => b.buyers.compareTo(a.buyers));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bets for sale'))),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              tr('Bets from pro bettors who passed the challenge. The pick shows once you buy it.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final l in sorted) ...[_listingCard(context, store, api, l), const SizedBox(height: 10)],
            const _PreviewNote(),
          ],
        ),
      ),
    );
  }
}

/// A free bet: the bettor, their followers and a follow button, the match
/// and the pick, open to everyone.
class FreeBetCard extends StatelessWidget {
  const FreeBetCard({super.key, required this.listing, required this.following, required this.onFollow, required this.onLog});
  final Listing listing;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = listing;
    final s = l.seller;
    final b = l.bet;
    final followers = s.followers + (following ? 1 : 0);
    return Card(
      key: Key('free-${l.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarImage(avatar: s.avatar, name: s.name, size: 40, border: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (s.pro) ...[const SizedBox(width: 4), Icon(Icons.verified, size: 16, color: cs.primary)],
                        ],
                      ),
                      Text(
                        l.mine
                            ? tr('@{handle} · your free bet', {'handle': s.handle})
                            : trn(followers, '@{handle} · {n} follower', '@{handle} · {n} followers', {'handle': s.handle}),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (!l.mine)
                  following
                      ? OutlinedButton(key: Key('follow-${s.handle}'), onPressed: onFollow, child: Text(tr('Following')))
                      : FilledButton.tonal(key: Key('follow-${s.handle}'), onPressed: onFollow, child: Text(tr('Follow'))),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                TeamLogo(url: b.homeLogo, name: b.home, size: 20),
                const SizedBox(width: 2),
                TeamLogo(url: b.awayLogo, name: b.away, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.matchTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${DateFormat.MMMd().add_Hm().format(b.kickoff.toLocal())} · ${b.leagueName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.leg.market.group, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      Text(
                        '${trPick(b.leg.pick)} @ ${b.leg.odds.toStringAsFixed(2)}',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                      ),
                    ],
                  ),
                ),
                if (b.settled)
                  Text(
                    b.won ? tr('Won') : tr('Lost'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: b.won ? BankColors.win(context) : BankColors.loss(context)),
                  )
                else if (!l.mine)
                  TextButton.icon(onPressed: onLog, icon: const Icon(Icons.add, size: 18), label: Text(tr('Log bet'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One bet for sale: the seller and their record, the match, and the pick
/// once bought.
class ListingCard extends StatelessWidget {
  const ListingCard(
      {super.key, required this.listing, required this.bought, required this.onBuy, required this.onLog, this.hot = false});
  final Listing listing;
  final bool bought;

  /// Shows how many bettors bought it, as the hottest bets do.
  final bool hot;
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
            if (hot && l.buyers > 0) ...[
              const SizedBox(width: 8),
              const Icon(Icons.local_fire_department, size: 18, color: Colors.deepOrange),
              Text(tr('{n} bought', {'n': l.buyers}),
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.deepOrange)),
            ],
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
              if (b.settled)
                Text(
                  b.won ? tr('Won') : tr('Lost'),
                  style: TextStyle(fontWeight: FontWeight.w800, color: b.won ? BankColors.win(context) : BankColors.loss(context)),
                )
              else if (!l.mine)
                TextButton.icon(onPressed: onLog, icon: const Icon(Icons.add, size: 18), label: Text(tr('Log bet'))),
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
      tr("Every challenge bet needs odds over 1.60, on a match that hasn't started."),
    ];

/// How the challenge goes, step by step, as the page explains it.
List<String> get challengeSteps => [
      tr('Accept the challenge from this page.'),
      tr('Place 30 bets on any matches, one at a time, each with odds over 1.60.'),
      tr('Each bet is settled from the final score of its match.'),
      tr('Win 60% or more of the 30 (18 bets) and you are a pro bettor: a verified badge and your own bets for sale.'),
    ];

/// Asks for a market of [m] at its price, only those priced over [above]
/// when set; null when the sheet is closed.
Future<TipLeg?> pickMarket(BuildContext context, FixturesApi api, Match m, {double? above}) async {
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
          Text(above == null ? tr('Pick your bet') : tr('Pick your bet: odds over {odds}', {'odds': above.toStringAsFixed(2)}),
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final leg in legs)
            if (above == null || leg.odds > above)
              ListTile(
              key: Key('market-${leg.market.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text(trPick(leg.pick), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(leg.market.group),
              trailing: Text(leg.odds.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: cs.primary)),
              onTap: () => Navigator.pop(context, leg),
            ),
        ]),
      );
    },
  );
}

/// Asks for a match of the day, then one of its markets.
Future<(Match, TipLeg)?> pickCommunityBet(BuildContext context, FixturesApi api, {DateTime? today, double? above}) async {
  final m = await Navigator.of(context).push<Match>(
    MaterialPageRoute(
      builder: (_) => StakeMatchPicker(api: api, today: today),
    ),
  );
  if (m == null || !context.mounted) return null;
  final leg = await pickMarket(context, api, m, above: above);
  return leg == null ? null : (m, leg);
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

  Future<void> _place() async {
    final picked = await pickCommunityBet(context, widget.api, today: widget.today, above: ProChallenge.minOdds);
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
    final picked = await pickCommunityBet(context, widget.api, today: widget.today);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Your bet is for sale in the community.'))));
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
            Text(tr('How it works'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final (i, line) in challengeSteps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: cs.primaryContainer,
                    child: Text('${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line)),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Requirements'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
