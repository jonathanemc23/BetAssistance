import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/account.dart';
import '../data/community_api.dart';
import '../data/fixtures.dart';
import '../data/models.dart' show isoDate;
import '../data/store.dart';
import '../l10n/l10n.dart';
import '../logic/community.dart';
import '../logic/pro_tips.dart';
import 'account_screens.dart' show LoginPage;
import 'bet_form.dart';
import 'format.dart';
import 'matches_screen.dart' show TeamLogo;
import 'pro_tips_page.dart' show TokenCoin, showTokensSheet;
import 'profile.dart';
import 'stake_builder.dart' show StakeMatchPicker;

Future<void> openCommunity(BuildContext context,
        {required BankStore store, required FixturesApi api, DateTime? today, AccountService? account}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPage(store: store, api: api, today: today, account: account),
      ),
    );

/// The pro bettor challenge on its own page: what it asks and where the user stands.
Future<void> openProBettor(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('Pro bettor challenge'))),
          body: ListenableBuilder(listenable: store, builder: (_, _) => _ProBettor(store: store, api: api, today: today)),
        ),
      ),
    );

/// The user's own community profile.
Future<void> openMyProfile(BuildContext context, {required BankStore store, required FixturesApi api, DateTime? today}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(tr('Your profile'))),
          body: ListenableBuilder(listenable: store, builder: (_, _) => _Profile(store: store, api: api, today: today)),
        ),
      ),
    );

/// Whether the user passed the pro bettor challenge.
bool _isPro(BankStore store) => store.challenge.status(communityClock()) == ChallengeStatus.passed;

/// The community: sign in, then a community profile with a nametag no one
/// else has, then the community itself.
class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key, required this.store, required this.api, this.today, this.account});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  /// The user's account; null in builds without accounts, where the
  /// community stays on this phone.
  final AccountService? account;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  CommunityApi? _api;

  /// Looking on the server for a profile this account made on another device.
  bool _restoring = false;
  String? _restoredFor;

  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account != null) _api = CommunityApi(account);
    account?.addListener(_accountChanged);
    _accountChanged();
  }

  @override
  void dispose() {
    widget.account?.removeListener(_accountChanged);
    super.dispose();
  }

  void _accountChanged() {
    final account = widget.account;
    if (account == null || !account.signedIn || store.socialProfile != null) {
      if (mounted) setState(() {});
      return;
    }
    final uid = account.account!.uid;
    if (_restoredFor == uid) return;
    _restoredFor = uid;
    _restore();
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final p = await _api!.myProfile();
    if (p != null && store.socialProfile == null) await store.saveSocialProfile(p);
    if (mounted) setState(() => _restoring = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final account = widget.account;
          if (account != null && !account.signedIn) {
            return Scaffold(appBar: AppBar(title: Text(tr('Community'))), body: _SignInGate(account: account));
          }
          final profile = store.socialProfile;
          if (profile == null) {
            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(backgroundColor: Colors.transparent),
              body: _restoring
                  ? const Center(child: CircularProgressIndicator())
                  : _CreateProfile(store: store, api: _api),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(tr('Community')),
              actions: [
                _TokenChip(store: store),
                IconButton(
                  key: const Key('community-profile'),
                  tooltip: tr('Your profile'),
                  onPressed: () => openMyProfile(context, store: store, api: widget.api, today: widget.today),
                  icon: AvatarImage(avatar: profile.avatar, name: profile.name, size: 32, border: false),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: _CommunityHome(store: store, api: widget.api, today: widget.today),
          );
        },
      );
}

/// The token balance next to the avatar; a tap offers more tokens.
class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.store});
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: InkWell(
          key: const Key('community-tokens'),
          customBorder: const StadiumBorder(),
          onTap: () => showTokensSheet(context, store),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const TokenCoin(size: 22),
              const SizedBox(width: 6),
              Text('${store.tokens}',
                  semanticsLabel: trn(store.tokens, '{n} token', '{n} tokens'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Asks the user to sign in before they can join the community.
class _SignInGate extends StatelessWidget {
  const _SignInGate({required this.account});
  final AccountService account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 32), children: [
      Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Icon(Icons.lock_person_outlined, size: 48, color: cs.onPrimary),
        ),
      ),
      const SizedBox(height: 20),
      Text(tr('Sign in to join the community'),
          textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(
        tr('Your community profile and nametag belong to your account, so other bettors know it is really you on any device.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const Key('community-sign-in'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LoginPage(account: account))),
        icon: const Icon(Icons.login),
        label: Text(tr('Sign in')),
      ),
    ]);
  }
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
            tr('Community preview: other bettors and their bets are simulated on this phone until the community goes online.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Profile

/// Whether a nametag is free, as the field shows it.
enum _HandleCheck { none, checking, available, taken, offline }

class _CreateProfile extends StatefulWidget {
  const _CreateProfile({required this.store, this.api});
  final BankStore store;

  /// Keeps nametags unique; null in builds without accounts.
  final CommunityApi? api;

  @override
  State<_CreateProfile> createState() => _CreateProfileState();
}

class _CreateProfileState extends State<_CreateProfile> {
  late final _name = TextEditingController(text: widget.store.profileName);
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  late final _avatar = ValueNotifier(
      widget.store.avatar.startsWith('legend:') || widget.store.avatar.startsWith('person:') ? widget.store.avatar : 'legend:dragon');
  String? _handleError;
  _HandleCheck _check = _HandleCheck.none;
  Timer? _debounce;
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _avatar.dispose();
    super.dispose();
  }

  void _handleChanged(String raw) {
    _debounce?.cancel();
    setState(() {
      _handleError = null;
      _check = _HandleCheck.none;
    });
    final api = widget.api;
    final handle = cleanHandle(raw);
    if (api == null || handle == null) return;
    setState(() => _check = _HandleCheck.checking);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final free = await api.handleAvailable(handle);
      if (!mounted || cleanHandle(_handle.text) != handle) return;
      setState(() => _check = switch (free) {
            true => _HandleCheck.available,
            false => _HandleCheck.taken,
            null => _HandleCheck.offline,
          });
    });
  }

  Future<void> _create() async {
    final handle = cleanHandle(_handle.text);
    if (handle == null) {
      setState(() => _handleError = tr('3 to 20 letters, digits or _'));
      return;
    }
    final name = _name.text.trim().isEmpty ? handle : _name.text.trim();
    final profile = SocialProfile(
      name: name,
      handle: handle,
      bio: _bio.text.trim(),
      avatar: _avatar.value,
      joined: communityClock().toIso8601String(),
    );
    final api = widget.api;
    if (api != null) {
      setState(() => _saving = true);
      final err = await api.createProfile(profile);
      if (!mounted) return;
      setState(() => _saving = false);
      if (err != null) {
        setState(() {
          _handleError = err;
          if (err == tr('That nametag is taken. Try another one.')) _check = _HandleCheck.taken;
        });
        return;
      }
    }
    await widget.store.saveSocialProfile(profile);
  }

  InputDecoration _field(BuildContext context, String label, {IconData? icon, String? prefix, String? error, Widget? suffix}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      prefixText: prefix,
      errorText: error,
      suffixIcon: suffix,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final status = switch (_check) {
      _HandleCheck.checking => const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      _HandleCheck.available => Icon(Icons.check_circle, color: BankColors.win(context)),
      _HandleCheck.taken => Icon(Icons.cancel, color: BankColors.loss(context)),
      _ => null,
    };
    final helper = switch (_check) {
      _HandleCheck.available => tr('@{handle} is yours to take', {'handle': cleanHandle(_handle.text) ?? ''}),
      _HandleCheck.taken => tr('That nametag is taken. Try another one.'),
      _HandleCheck.offline => tr("Couldn't check the nametag right now."),
      _ => tr('Your unique nametag: 3 to 20 letters, digits or _'),
    };
    return ListView(padding: EdgeInsets.zero, children: [
      // A hero with the invitation, the avatar overlapping its bottom edge.
      Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, top + 8, 24, 72),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: cs.onPrimary.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(tr('Community'),
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 14),
            Text(tr('Join the community'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              tr('Find the best picks and analysis from the top bettors in the app, follow the ones you trust, and become a pro bettor yourself.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.9)),
            ),
          ]),
        ),
        Positioned(
          bottom: -52,
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
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: theme.scaffoldBackgroundColor, shape: BoxShape.circle),
                child: Stack(children: [
                  AvatarImage(avatar: avatar, name: _name.text, size: 100),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: CircleAvatar(radius: 15, backgroundColor: cs.primary, child: Icon(Icons.edit, size: 16, color: cs.onPrimary)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 68, 20, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const Key('community-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: _field(context, tr('Name'), icon: Icons.person_outline),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('community-handle'),
            controller: _handle,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[@\s]'))],
            decoration: _field(context, tr('Nametag'), icon: Icons.alternate_email, error: _handleError, suffix: status)
                .copyWith(helperText: helper),
            onChanged: _handleChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('community-bio'),
            controller: _bio,
            maxLines: 3,
            maxLength: 120,
            decoration: _field(context, tr('Description (optional)'), icon: Icons.notes)
                .copyWith(hintText: tr('What you bet on, your favourite leagues...')),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('community-create'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _saving || _check == _HandleCheck.taken ? null : _create,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.how_to_reg),
            label: Text(tr('Create profile and join')),
          ),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final (icon, text) in [
              (Icons.card_giftcard, tr('Free bets')),
              (Icons.local_fire_department, tr('Hottest bets')),
              (Icons.workspace_premium, tr('Pro bettors')),
            ])
              Chip(avatar: Icon(icon, size: 18, color: cs.primary), label: Text(text), side: BorderSide.none),
          ]),
        ]),
      ),
    ]);
  }
}

/// The user's own profile: Following for everyone; followers and the record
/// of the bets they sold once they are a pro bettor, who also manage their
/// sales from here. The challenge starts from here.
class _Profile extends StatelessWidget {
  const _Profile({required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  Future<void> _edit(BuildContext context, SocialProfile p) async {
    final bio = TextEditingController(text: p.bio);
    final name = TextEditingController(text: p.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Edit profile')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
          TextField(controller: bio, maxLength: 120, decoration: InputDecoration(labelText: tr('Description (optional)'))),
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
    final pro = _isPro(store);
    final joined = DateTime.tryParse(p.joined);
    final sold = store.myListings;
    final soldSettled = [for (final l in sold) if (l.bet.settled) l];
    final soldWon = soldSettled.where((l) => l.bet.won).length;
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
          child: AvatarImage(avatar: p.avatar, name: p.name, size: 104),
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Text(p.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        if (pro) ...[const SizedBox(width: 6), Icon(Icons.verified, color: cs.primary)],
      ]),
      Text('@${p.handle}', textAlign: TextAlign.center, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(20)),
          child: Text(pro ? tr('Pro bettor') : tr('Member'),
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w800)),
        ),
      ),
      if (p.bio.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(p.bio, textAlign: TextAlign.center),
      ],
      if (joined != null) ...[
        const SizedBox(height: 4),
        Text(tr('Joined {date}', {'date': DateFormat.yMMMd().format(joined)}),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          if (pro) _Stat(value: '0', label: tr('Followers')),
          _Stat(value: '${store.following.length}', label: tr('Following'), key: const Key('profile-following')),
          if (pro) ...[
            _Stat(value: '${sold.length}', label: tr('Bets sold')),
            _Stat(value: '$soldWon-${soldSettled.length - soldWon}', label: tr('Won-lost')),
            _Stat(value: soldSettled.isEmpty ? '-' : '${soldWon * 100 ~/ soldSettled.length}%', label: tr('Win rate')),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      if (!pro)
        _PassChallengeButton(onTap: () => openProBettor(context, store: store, api: api, today: today))
      else
        FilledButton.tonalIcon(
          key: const Key('profile-pro-page'),
          onPressed: () => openProBettor(context, store: store, api: api, today: today),
          icon: const Icon(Icons.sell_outlined),
          label: Text(tr('Sell a bet')),
        ),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => _edit(context, p), icon: const Icon(Icons.edit_outlined), label: Text(tr('Edit profile'))),
      const _PreviewNote(),
    ]);
  }
}

/// The one button that opens the pro bettor challenge.
class _PassChallengeButton extends StatelessWidget {
  const _PassChallengeButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cs.primary, cs.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: InkWell(
          key: const Key('profile-pass-challenge'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              Icon(Icons.workspace_premium, color: cs.onPrimary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('Pass the challenge, become a pro bettor'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900)),
              ),
              Icon(Icons.chevron_right, color: cs.onPrimary),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label});
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
Widget _listingCard(BuildContext context, BankStore store, FixturesApi api, Listing l, {bool hot = false, VoidCallback? onBettor}) {
  final bought = store.boughtListings;
  return ListingCard(
    listing: bought[l.id] ?? l,
    bought: l.mine || bought.containsKey(l.id),
    hot: hot,
    onBettor: onBettor,
    onBuy: () => _buy(context, store, l),
    onLog: () => _log(context, store, api, l),
  );
}

/// The user's own bets for sale that are still worth showing.
Iterable<Listing> _myOpenListings(BankStore store) =>
    store.myListings.where((l) => l.bet.kickoff.isAfter(communityClock().subtract(const Duration(hours: 3))));

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 2),
        Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// The bettors the community knows by handle, for their avatar and record.
ProSeller? _bettorByHandle(String handle) =>
    [...demoSellers, ...demoTipsters].where((s) => s.handle == handle).firstOrNull;

/// Opens [s]'s public profile, or the user's own.
void _openBettor(BuildContext context, BankStore store, FixturesApi api, ProSeller s, {DateTime? today}) {
  if (s.handle == store.socialProfile?.handle) {
    openMyProfile(context, store: store, api: api, today: today);
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BettorProfilePage(store: store, bettor: s)));
}

/// A small alert inviting the user to become a pro bettor; it can be closed,
/// and a tap opens the profile, where the challenge starts.
class _ProAlert extends StatelessWidget {
  const _ProAlert({required this.onOpen, required this.onClose});
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('community-pro-alert'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(children: [
            Icon(Icons.workspace_premium, color: cs.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Become a pro bettor'),
                  style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              key: const Key('community-pro-alert-close'),
              tooltip: tr('Close'),
              onPressed: onClose,
              icon: Icon(Icons.close, color: cs.onTertiaryContainer),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One of the hottest bets for sale in the carousel.
class _HotCard extends StatelessWidget {
  const _HotCard({required this.listing, required this.bought, required this.onBuy, required this.onBettor});
  final Listing listing;
  final bool bought;
  final VoidCallback onBuy;
  final VoidCallback onBettor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = listing;
    final b = l.bet;
    return Container(
      key: Key('hot-${l.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.surfaceContainerHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: InkWell(
              key: Key('hot-bettor-${l.id}'),
              onTap: onBettor,
              borderRadius: BorderRadius.circular(20),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AvatarImage(avatar: l.seller.avatar, name: l.seller.name, size: 30, border: false),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(l.seller.name,
                      overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 3),
                Icon(Icons.verified, size: 15, color: cs.primary),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.local_fire_department, size: 18, color: Colors.deepOrange),
          Text(tr('{n} bought', {'n': l.buyers}),
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.deepOrange)),
        ]),
        const Spacer(),
        Text(b.matchTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Text('${DateFormat.MMMd().add_Hm().format(b.kickoff.toLocal())} · ${b.leagueName}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: bought
                ? Text('${trPick(b.leg.pick)} @ ${b.leg.odds.toStringAsFixed(2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: cs.primary))
                : Row(children: [
                    Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(b.leg.market.group,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ]),
          ),
          if (!bought)
            FilledButton(
              key: Key('hot-buy-${l.id}'),
              onPressed: onBuy,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const TokenCoin(size: 16),
                const SizedBox(width: 4),
                Text('${l.price}'),
              ]),
            ),
        ]),
      ]),
    );
  }
}

/// The parts of the community, switched like the sports in Matches.
enum _Tab { free, buy, history, chat }

/// The community's front page: a closable pro bettor alert, a carousel of
/// the hottest bets for sale, then Free bets, Buy bets, History and Chat.
class _CommunityHome extends StatefulWidget {
  const _CommunityHome({required this.store, required this.api, this.today});
  final BankStore store;
  final FixturesApi api;
  final DateTime? today;

  @override
  State<_CommunityHome> createState() => _CommunityHomeState();
}

class _CommunityHomeState extends State<_CommunityHome> {
  static const _alertPref = 'community.proAlertClosed';

  List<Listing>? _listings;
  List<Listing>? _free;
  String? _error;
  _Tab _tab = _Tab.free;
  bool _alertClosed = true;

  BankStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
    _settleFreeBets();
    store.pref(_alertPref).then((v) {
      if (mounted) setState(() => _alertClosed = v == '1');
    });
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

  Future<void> _closeAlert() async {
    setState(() => _alertClosed = true);
    await store.setPref(_alertPref, '1');
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
          pro: _isPro(store),
        ),
        bet: CommunityBet.on(m, leg, placed: communityClock().toIso8601String()),
        price: 0,
        mine: true,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? tr('Your free bet is posted for your followers.'))));
  }

  void _bettor(ProSeller s) => _openBettor(context, store, widget.api, s, today: widget.today);

  Widget _loading(ColorScheme cs) => _error != null
      ? Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: Text(tr('Try again'))),
          ]),
        )
      : const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));

  Widget _empty(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      );

  List<Widget> _freeTab(ColorScheme cs) {
    final now = communityClock();
    final myFree = store.myFreeBets.reversed.where((l) => l.bet.kickoff.isAfter(now.subtract(const Duration(days: 2))));
    return [
      Text(tr('Bettors post free bets to gain followers. Follow the ones you like, or post your own.'),
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('community-post-free'),
        onPressed: _postFree,
        icon: const Icon(Icons.add),
        label: Text(tr('Post a free bet')),
      ),
      const SizedBox(height: 10),
      if (_free == null) _loading(cs),
      for (final l in [...myFree, ...?_free]) ...[
        FreeBetCard(
          listing: l,
          following: store.following.contains(l.seller.handle),
          onFollow: () => store.toggleFollow(l.seller.handle),
          onLog: () => _log(context, store, widget.api, l),
          onBettor: () => _bettor(l.seller),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _buyTab(ColorScheme cs, List<Listing> listings) {
    final sorted = [...listings]..sort((a, b) => b.buyers.compareTo(a.buyers));
    return [
      Text(tr('Bets from pro bettors who passed the challenge. The pick shows once you buy it.'),
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      if (_listings == null) _loading(cs),
      if (_listings != null && sorted.isEmpty) _empty(cs, tr('No bets for sale right now. Come back closer to the next big matches.')),
      for (final l in sorted) ...[
        _listingCard(context, store, widget.api, l, hot: true, onBettor: () => _bettor(l.seller)),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _historyTab(ColorScheme cs) {
    final bought = [...store.boughtListings.values]..sort((a, b) => b.bet.kickoff.compareTo(a.bet.kickoff));
    final free = store.myFreeBets.reversed.toList();
    final wins = bought.where((l) => l.bet.won).length, settled = bought.where((l) => l.bet.settled).length;
    return [
      if (bought.isEmpty && free.isEmpty) _empty(cs, tr('The bets you buy and the free bets you post show here with their results.')),
      if (bought.isNotEmpty) ...[
        _SectionTitle(
          icon: Icons.receipt_long,
          title: tr('Bets you bought'),
          text: settled == 0
              ? tr('Their result comes in on its own once the match is over.')
              : tr('{w} of {s} won', {'w': wins, 's': settled}),
        ),
        for (final l in bought) ...[
          _listingCard(context, store, widget.api, l, onBettor: () => _bettor(l.seller)),
          const SizedBox(height: 10),
        ],
      ],
      if (free.isNotEmpty) ...[
        _SectionTitle(
          icon: Icons.card_giftcard,
          title: tr('Your free bets'),
          text: tr('Their result comes in on its own once the match is over.'),
        ),
        for (final l in free)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${trPick(l.bet.leg.pick)} @ ${l.bet.leg.odds.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(l.bet.matchTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _ResultText(bet: l.bet),
          ),
      ],
    ];
  }

  List<Widget> _chatTab(ColorScheme cs) {
    final chats = store.chats.entries.where((e) => e.value.isNotEmpty).toList()
      ..sort((a, b) => b.value.last.at.compareTo(a.value.last.at));
    if (chats.isEmpty) return [_empty(cs, tr("Open a bettor's profile and tap Message to start a chat."))];
    return [
      for (final e in chats)
        if (_bettorByHandle(e.key) case final s?)
          ListTile(
            key: Key('chat-${s.handle}'),
            contentPadding: EdgeInsets.zero,
            leading: AvatarImage(avatar: s.avatar, name: s.name, size: 44, border: false),
            title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(e.value.last.text, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(DateFormat.MMMd().format(e.value.last.at.toLocal()),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            onTap: () => openChat(context, store, s),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final listings = [..._myOpenListings(store), ...?_listings];
    final hot = hottest(listings, n: 5);
    final bought = store.boughtListings;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (!_alertClosed && !_isPro(store)) ...[
          _ProAlert(
            onOpen: () => openMyProfile(context, store: store, api: widget.api, today: widget.today),
            onClose: _closeAlert,
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          const Icon(Icons.local_fire_department, color: Colors.deepOrange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('Hottest bets to buy'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 10),
        if (_listings == null) _loading(cs),
        if (_listings != null && hot.isEmpty) _empty(cs, tr('No bets for sale right now. Come back closer to the next big matches.')),
        if (hot.isNotEmpty)
          SizedBox(
            height: 168,
            child: PageView(
              key: const Key('community-hot-carousel'),
              controller: PageController(viewportFraction: 0.9),
              padEnds: false,
              children: [
                for (final l in hot)
                  _HotCard(
                    listing: bought[l.id] ?? l,
                    bought: l.mine || bought.containsKey(l.id),
                    onBuy: () => _buy(context, store, l),
                    onBettor: () => _bettor(l.seller),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Tab>(
            key: const Key('community-tabs'),
            showSelectedIcon: false,
            segments: [
              for (final (t, icon, label) in [
                (_Tab.free, Icons.card_giftcard, tr('Free bets')),
                (_Tab.buy, Icons.storefront_outlined, tr('Buy bets')),
                (_Tab.history, Icons.history, tr('History')),
                (_Tab.chat, Icons.chat_bubble_outline, tr('Chat')),
              ])
                ButtonSegment(
                  value: t,
                  icon: Icon(icon, size: 18),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, key: Key('community-tab-${t.name}'))),
                ),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ),
        const SizedBox(height: 14),
        ...switch (_tab) {
          _Tab.free => _freeTab(cs),
          _Tab.buy => _buyTab(cs, listings),
          _Tab.history => _historyTab(cs),
          _Tab.chat => _chatTab(cs),
        },
        const _PreviewNote(),
      ]),
    );
  }
}

/// Won, Lost or Pending, in its colour.
class _ResultText extends StatelessWidget {
  const _ResultText({required this.bet});
  final CommunityBet bet;

  @override
  Widget build(BuildContext context) => Text(
        bet.settled ? (bet.won ? tr('Won') : tr('Lost')) : tr('Pending'),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: !bet.settled
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : (bet.won ? BankColors.win(context) : BankColors.loss(context)),
        ),
      );
}

/// Five stars, filled up to [value].
class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.size = 18});
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i ? Icons.star_rounded : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: Colors.amber.shade600,
          ),
      ]);
}

/// A bettor's public profile: bets sold, win rate, average odds, stars and
/// comments, with follow, rate and send message.
class BettorProfilePage extends StatelessWidget {
  const BettorProfilePage({super.key, required this.store, required this.bettor});
  final BankStore store;
  final ProSeller bettor;

  Future<void> _rate(BuildContext context) async {
    final me = store.socialProfile!;
    final old = store.myReviews[bettor.handle];
    var stars = old?.stars ?? 5;
    final text = TextEditingController(text: old?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Rate @{handle}', {'handle': bettor.handle})),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: Key('rate-star-$i'),
                  onPressed: () => setState(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: Colors.amber.shade600, size: 32),
                ),
            ]),
            TextField(
              key: const Key('rate-comment'),
              controller: text,
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(labelText: tr('Comment (optional)')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await store.reviewBettor(
          bettor.handle, Review(handle: me.handle, name: me.name, stars: stars, text: text.text.trim(), at: communityClock()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('@${bettor.handle}')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = bettor;
          final following = store.following.contains(s.handle);
          final stats = demoBettorStats(s, mine: store.myReviews[s.handle], now: communityClock());
          final rate = stats.winRate;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            Center(child: AvatarImage(avatar: s.avatar, name: s.name, size: 96)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(s.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              if (s.pro) ...[const SizedBox(width: 6), Icon(Icons.verified, color: cs.primary)],
            ]),
            Text(
              s.pro
                  ? trn(s.followers + (following ? 1 : 0), '@{handle} · {n} follower', '@{handle} · {n} followers', {'handle': s.handle})
                  : '@${s.handle}',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Stars(value: stats.stars),
              const SizedBox(width: 6),
              Text(stats.reviews.isEmpty ? tr('No ratings yet') : '${stats.stars.toStringAsFixed(1)} (${stats.reviews.length})',
                  key: const Key('bettor-stars'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: following
                    ? OutlinedButton(
                        key: const Key('bettor-follow'), onPressed: () => store.toggleFollow(s.handle), child: Text(tr('Following')))
                    : FilledButton(
                        key: const Key('bettor-follow'), onPressed: () => store.toggleFollow(s.handle), child: Text(tr('Follow'))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('bettor-message'),
                  onPressed: () => openChat(context, store, s),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(tr('Message')),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                _Stat(value: '${stats.betsSold}', label: tr('Bets sold'), key: const Key('bettor-sold')),
                _Stat(value: rate == null ? '-' : '${(rate * 100).round()}%', label: tr('Win rate')),
                _Stat(value: stats.averageOdds.toStringAsFixed(2), label: tr('Average odds')),
                _Stat(value: stats.reviews.isEmpty ? '-' : stats.stars.toStringAsFixed(1), label: tr('Stars')),
              ]),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Text(tr('Comments'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              TextButton.icon(
                key: const Key('bettor-rate'),
                onPressed: () => _rate(context),
                icon: const Icon(Icons.star_outline_rounded),
                label: Text(store.myReviews.containsKey(s.handle) ? tr('Edit your rating') : tr('Rate')),
              ),
            ]),
            if (stats.reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('No comments yet. Be the first to rate this bettor.'), style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final r in stats.reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      _Stars(value: r.stars.toDouble(), size: 15),
                    ]),
                    Text('@${r.handle} · ${DateFormat.yMMMd().format(r.at.toLocal())}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    if (r.text.isNotEmpty) ...[const SizedBox(height: 6), Text(r.text)],
                  ]),
                ),
              ),
            const _PreviewNote(),
          ]);
        },
      ),
    );
  }
}

/// Opens the chat with [s].
Future<void> openChat(BuildContext context, BankStore store, ProSeller s) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ChatPage(store: store, bettor: s)));

class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.store, required this.bettor});
  final BankStore store;
  final ProSeller bettor;

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await widget.store.sendChat(widget.bettor.handle, ChatMessage(text: t, at: communityClock()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.bettor;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          AvatarImage(avatar: s.avatar, name: s.name, size: 34, border: false),
          const SizedBox(width: 10),
          Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final messages = widget.store.chats[s.handle] ?? const [];
          return Column(children: [
            Expanded(
              child: ListView(reverse: true, padding: const EdgeInsets.all(16), children: [
                for (final m in messages.reversed)
                  Align(
                    alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: const BoxConstraints(maxWidth: 300),
                      decoration: BoxDecoration(
                        color: m.mine ? cs.primary : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(m.text, style: TextStyle(color: m.mine ? cs.onPrimary : cs.onSurface)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    tr('Messages wait on this phone and are delivered once the community goes online.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-input'),
                      controller: _text,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: tr('Message @{handle}', {'handle': s.handle}),
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(key: const Key('chat-send'), tooltip: tr('Send'), onPressed: _send, icon: const Icon(Icons.send)),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// A free bet: the bettor, their followers and a follow button, the match
/// and the pick, open to everyone.
class FreeBetCard extends StatelessWidget {
  const FreeBetCard(
      {super.key, required this.listing, required this.following, required this.onFollow, required this.onLog, this.onBettor});
  final Listing listing;
  final bool following;
  final VoidCallback onFollow;
  final VoidCallback onLog;

  /// Opens the bettor's public profile.
  final VoidCallback? onBettor;

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
                InkWell(
                  key: Key('avatar-${l.id}'),
                  customBorder: const CircleBorder(),
                  onTap: onBettor,
                  child: AvatarImage(avatar: s.avatar, name: s.name, size: 40, border: false),
                ),
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
      {super.key,
      required this.listing,
      required this.bought,
      required this.onBuy,
      required this.onLog,
      this.hot = false,
      this.onBettor});
  final Listing listing;
  final bool bought;

  /// Opens the seller's public profile.
  final VoidCallback? onBettor;

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
            InkWell(
              key: Key('avatar-${l.id}'),
              customBorder: const CircleBorder(),
              onTap: onBettor,
              child: AvatarImage(avatar: s.avatar, name: s.name, size: 40, border: false),
            ),
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
