import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/account.dart';
import '../data/sync.dart';
import '../l10n/l10n.dart';

/// Sign in or create an account with an email and password, or with Google
/// in the web app. Pops true once signed in. At launch ([atLaunch]) it also
/// offers "Not now", remembered so the page doesn't come back every time.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.account, this.atLaunch = false});
  final AccountService account;
  final bool atLaunch;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  AccountService get account => widget.account;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final error = await call();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && account.signedIn) Navigator.pop(context, true);
  }

  Future<void> _submit() => _run(
      () => _create ? account.signUp(_email.text, _password.text) : account.signIn(_email.text, _password.text));

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final error = await account.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _info = tr('We sent you an email with a link to choose a new password.');
    });
  }

  Future<void> _notNow() async {
    await account.store.setPref(accountSkippedPref, '1');
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Account')),
        automaticallyImplyLeading: !widget.atLaunch,
        actions: [
          if (widget.atLaunch)
            TextButton(key: const Key('login-not-now'), onPressed: _busy ? null : _notNow, child: Text(tr('Not now'))),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
            Text(_create ? tr('Create your account') : tr('Sign in'),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              tr('Your bets, bankroll and parlays are saved on your account, so they are safe if you lose your phone and you see them on any device you sign in on.'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (account.googleAvailable) ...[
              OutlinedButton.icon(
                key: const Key('login-google'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                label: Text(tr('Continue with Google')),
                onPressed: _busy ? null : () => _run(account.signInWithGoogle),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('or with your email'))),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const Key('login-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: tr('Email')),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login-password'),
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [_create ? AutofillHints.newPassword : AutofillHints.password],
              onSubmitted: (_) => _busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: tr('Password'),
                helperText: _create ? tr('At least 6 characters') : null,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? tr('Hide') : tr('Show'),
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, key: const Key('login-error'), style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: TextStyle(color: theme.colorScheme.primary)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('login-submit'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_create ? tr('Create account') : tr('Sign in')),
            ),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.spaceBetween, children: [
              TextButton(
                key: const Key('login-switch'),
                onPressed: _busy ? null : () => setState(() {
                  _create = !_create;
                  _error = null;
                  _info = null;
                }),
                child: Text(_create ? tr('I already have an account') : tr('Create an account')),
              ),
              if (!_create) TextButton(onPressed: _busy ? null : _reset, child: Text(tr('Forgot password?'))),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The signed-in account: whether the data is saved, sync now, sign out.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.account, required this.sync});
  final AccountService account;
  final SyncService sync;

  String _status() => switch (sync.state) {
        SyncState.off => tr('Not syncing'),
        SyncState.syncing => tr('Saving to your account…'),
        SyncState.synced => sync.lastSynced == null
            ? tr('Saved on your account')
            : tr('Saved on your account at {time}', {'time': DateFormat.Hm().format(sync.lastSynced!)}),
        SyncState.offline => tr("Couldn't reach the server. Your changes are kept on this device and saved when it's back."),
        SyncState.needsChoice => tr('Choose which data to keep below.'),
        SyncState.error => sync.message ?? tr('Saving to your account failed.'),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([account, sync]),
        builder: (context, _) {
          final a = account.account;
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(title: Text(tr('Account'))),
            body: a == null
                ? Center(
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute<bool>(builder: (_) => LoginPage(account: account))),
                      child: Text(tr('Sign in')),
                    ),
                  )
                : ListView(padding: const EdgeInsets.all(16), children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Icon(a.provider == 'google.com' ? Icons.g_mobiledata : Icons.mail_outline)),
                      title: Text(a.email.isEmpty ? tr('Signed in') : a.email, key: const Key('account-email')),
                      subtitle: Text(a.provider == 'google.com' ? tr('Google account') : tr('Email and password')),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (sync.state) {
                        SyncState.synced => Icons.cloud_done_outlined,
                        SyncState.syncing => Icons.cloud_sync_outlined,
                        SyncState.needsChoice => Icons.help_outline,
                        _ => Icons.cloud_off_outlined,
                      }),
                      title: Text(_status(), key: const Key('sync-status')),
                    ),
                    if (sync.state == SyncState.needsChoice) ...[
                      const SizedBox(height: 8),
                      SyncChoice(sync: sync),
                    ] else
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.sync),
                          label: Text(tr('Sync now')),
                          onPressed: sync.state == SyncState.syncing ? null : sync.sync,
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      tr('Signing out keeps your data on this device and on your account.'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('sign-out'),
                        icon: const Icon(Icons.logout),
                        label: Text(tr('Sign out')),
                        onPressed: () async {
                          await account.signOut();
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ]),
          );
        },
      );
}

/// The two ways out when this device and the account both have data.
class SyncChoice extends StatelessWidget {
  const SyncChoice({super.key, required this.sync, this.onChosen});
  final SyncService sync;
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('This device and your account have different data. Which do you want to keep? The other copy is replaced.')),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('sync-keep-account'),
          onPressed: () {
            onChosen?.call();
            sync.choose(keepAccount: true);
          },
          child: Text(tr("Use my account's data")),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('sync-keep-device'),
          onPressed: () {
            onChosen?.call();
            sync.choose(keepAccount: false);
          },
          child: Text(tr("Keep this device's data")),
        ),
      ]);
}

/// Asks which data to keep, from anywhere in the app.
Future<void> showSyncChoice(BuildContext context, SyncService sync) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Your account already has data')),
        content: SingleChildScrollView(child: SyncChoice(sync: sync, onChosen: () => Navigator.pop(ctx))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Decide later')))],
      ),
    );
