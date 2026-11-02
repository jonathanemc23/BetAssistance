import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/account.dart';
import '../data/store.dart';
import '../data/sync.dart';
import '../l10n/l10n.dart';
import 'profile.dart';
import 'themes.dart';

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
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _info;

  AccountService get account => widget.account;

  @override
  void initState() {
    super.initState();
    account.prepareGoogle();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _mode(bool create) => setState(() {
        _create = create;
        _error = null;
        _info = null;
      });

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

  Future<void> _submit() => _run(() async {
        if (!_create) return account.signIn(_email.text, _password.text);
        final error = await account.signUp(_email.text, _password.text);
        // The name on the new account becomes the profile name, unless one
        // is already set on this device.
        final name = _name.text.trim();
        if (error == null && name.isNotEmpty && account.store.profileName.isEmpty) {
          await account.store.setProfileName(name);
        }
        return error;
      });

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

  InputDecoration _field(String label, IconData icon, {String? helper, Widget? suffix}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.primary, width: 1.6)),
    );
  }

  Widget _notice(String text, {required bool error, Key? key}) {
    final cs = Theme.of(context).colorScheme;
    final color = error ? cs.error : cs.primary;
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_outline : Icons.mark_email_read_outlined, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hero = HeroColors.of(context);

    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _ModeSwitch(create: _create, onChanged: _busy ? null : _mode),
      const SizedBox(height: 20),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Column(
          key: ValueKey(_create),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_create ? tr('Create your account') : tr('Welcome back'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              _create
                  ? tr('Free. Your bets are backed up and on every device you sign in on.')
                  : tr('Sign in to pick up your bets and bankroll on this device.'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (account.googleAvailable) ...[
        _GoogleButton(key: const Key('login-google'), onPressed: _busy ? null : () => _run(account.signInWithGoogle)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Divider(color: cs.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(tr('or with your email'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(child: Divider(color: cs.outlineVariant)),
        ]),
        const SizedBox(height: 18),
      ],
      AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_create) ...[
            TextField(
              key: const Key('login-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: _field(tr('Your name'), Icons.person_outline),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const Key('login-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: _field(tr('Email'), Icons.mail_outline),
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
            decoration: _field(
              tr('Password'),
              Icons.lock_outline,
              helper: _create ? tr('At least 6 characters') : null,
              suffix: IconButton(
                tooltip: _showPassword ? tr('Hide') : tr('Show'),
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        ]),
      ),
      if (!_create)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(onPressed: _busy ? null : _reset, child: Text(tr('Forgot password?'))),
        )
      else
        const SizedBox(height: 14),
      if (_error != null) ...[
        _notice(_error!, error: true, key: const Key('login-error')),
        const SizedBox(height: 12),
      ],
      if (_info != null) ...[
        _notice(_info!, error: false),
        const SizedBox(height: 12),
      ],
      _PrimaryButton(
        key: const Key('login-submit'),
        busy: _busy,
        label: _create ? tr('Create account') : tr('Sign in'),
        onPressed: _busy ? null : _submit,
      ),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(_create ? tr('Already have an account?') : tr("Don't have an account?"),
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        TextButton(
          key: const Key('login-switch'),
          onPressed: _busy ? null : () => _mode(!_create),
          child: Text(_create ? tr('Sign in') : tr('Create one'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    ]);

    return Scaffold(
      body: Stack(children: [
        // Backdrop: the theme's header colours fading into the page, with a
        // soft glow and a rising line like the app's charts.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.42, 0.75],
                colors: [hero.gradient.first, hero.gradient.last, theme.scaffoldBackgroundColor],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 340,
          child: CustomPaint(painter: _BackdropPainter(glow: cs.primary, line: hero.onGradient)),
        ),
        SafeArea(
          child: Column(children: [
            SizedBox(
              height: 48,
              child: Row(children: [
                if (!widget.atLaunch)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    color: hero.onGradient,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                const Spacer(),
                if (widget.atLaunch)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      key: const Key('login-not-now'),
                      style: TextButton.styleFrom(
                        foregroundColor: hero.onGradient,
                        backgroundColor: hero.onGradient.withValues(alpha: 0.12),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _busy ? null : _notNow,
                      child: Text(tr('Not now')),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  // Room above the logo so its glow is not cut off.
                  padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _Brand(color: hero.onGradient, glow: cs.primary),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 14))],
                        ),
                        child: form,
                      ),
                      const SizedBox(height: 22),
                      _Perks(),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The app icon with a glow, the name and the tagline.
class _Brand extends StatelessWidget {
  const _Brand({required this.color, required this.glow});
  final Color color;
  final Color glow;

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 36, spreadRadius: 2),
              const BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 6)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset('assets/brand/icon.png', width: 92, height: 92),
          ),
        ),
        const SizedBox(height: 16),
        Text('BetPilot',
            style: TextStyle(color: color, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 0.3, height: 1.1)),
        const SizedBox(height: 6),
        Text(tr('Track every bet. Grow your bank.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: color.withValues(alpha: 0.78), fontSize: 15, fontWeight: FontWeight.w500)),
      ]);
}

/// Sign in | Create account, as a pill with a sliding thumb.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.create, required this.onChanged});
  final bool create;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tab(String label, bool value) => Expanded(
          child: InkWell(
            key: Key(value ? 'login-tab-create' : 'login-tab-signin'),
            borderRadius: BorderRadius.circular(14),
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: create == value ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        );
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: create ? Alignment.centerRight : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.white, 0.18)!]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
              ),
            ),
          ),
        ),
        Row(children: [tab(tr('Sign in'), false), tab(tr('Create account'), true)]),
      ]),
    );
  }
}

/// The main action: a tall gradient button that shows progress.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({super.key, required this.label, required this.busy, this.onPressed});
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.white, 0.2)!]),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: SizedBox(
              height: 54,
              child: Center(
                child: busy
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimary))
                    : Text(label, style: TextStyle(color: cs.onPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Continue with Google" in Google's own style: white, with the coloured G.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1F1F1F),
            side: const BorderSide(color: Color(0xFFDADCE0)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onPressed,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GoogleLogoPainter())),
            const SizedBox(width: 12),
            Flexible(
              child: Text(tr('Continue with Google'),
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ]),
        ),
      );
}

/// Google's G: four coloured arcs and the bar.
class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromCircle(center: Offset(s / 2, s / 2), radius: (s - stroke) / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    double deg(double d) => d * math.pi / 180;
    p.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, deg(-8), deg(53), false, p);
    p.color = const Color(0xFF34A853);
    canvas.drawArc(rect, deg(45), deg(90), false, p);
    p.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, deg(135), deg(80), false, p);
    p.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, deg(215), deg(100), false, p);
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A soft glow and a faint rising chart line behind the logo.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.glow, required this.line});
  final Color glow;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawCircle(
      Offset(w * 0.85, h * 0.12),
      w * 0.45,
      Paint()
        ..shader = RadialGradient(colors: [glow.withValues(alpha: 0.28), glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(w * 0.85, h * 0.12), radius: w * 0.45)),
    );
    canvas.drawCircle(
      Offset(w * 0.08, h * 0.55),
      w * 0.35,
      Paint()
        ..shader = RadialGradient(colors: [glow.withValues(alpha: 0.16), glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(w * 0.08, h * 0.55), radius: w * 0.35)),
    );
    final pts = [
      Offset(0, h * 0.86),
      Offset(w * 0.16, h * 0.78),
      Offset(w * 0.3, h * 0.82),
      Offset(w * 0.46, h * 0.64),
      Offset(w * 0.6, h * 0.69),
      Offset(w * 0.76, h * 0.46),
      Offset(w * 0.88, h * 0.5),
      Offset(w, h * 0.3),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) {
      path.lineTo(pt.dx, pt.dy);
    }
    final area = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [glow.withValues(alpha: 0.14), glow.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, h * 0.3, w, h * 0.7)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = line.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.glow != glow || old.line != line;
}

/// What an account gives, under the form.
class _Perks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget perk(IconData icon, String text) => Expanded(
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: cs.primary),
            ),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      perk(Icons.cloud_done_outlined, tr('Backed up')),
      perk(Icons.devices_outlined, tr('On every device')),
      perk(Icons.lock_outline, tr('Only you see it')),
    ]);
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
                    _AccountCard(account: a, store: account.store),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _statusColor(theme.colorScheme).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                switch (sync.state) {
                                  SyncState.synced => Icons.cloud_done_outlined,
                                  SyncState.syncing => Icons.cloud_sync_outlined,
                                  SyncState.needsChoice => Icons.help_outline,
                                  _ => Icons.cloud_off_outlined,
                                },
                                size: 20,
                                color: _statusColor(theme.colorScheme),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_status(),
                                  key: const Key('sync-status'),
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          if (sync.state == SyncState.needsChoice)
                            SyncChoice(sync: sync)
                          else
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.sync),
                              label: Text(tr('Sync now')),
                              onPressed: sync.state == SyncState.syncing ? null : sync.sync,
                            ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tr('Your data stays safe on your account. Signing out removes it from this device until you sign in again.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        key: const Key('sign-out'),
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        icon: const Icon(Icons.logout),
                        label: Text(tr('Sign out')),
                        onPressed: () => signOutAndClear(context, account: account, sync: sync),
                      ),
                    ),
                  ]),
          );
        },
      );

  Color _statusColor(ColorScheme cs) => switch (sync.state) {
        SyncState.synced => const Color(0xFF2E9461),
        SyncState.offline || SyncState.error => cs.error,
        _ => cs.primary,
      };
}

/// The account at the top of the Account page: avatar, name, email and how
/// the user signs in, on the theme's header colours.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.store});
  final Account account;
  final BankStore store;

  @override
  Widget build(BuildContext context) {
    final hero = HeroColors.of(context);
    final fg = hero.onGradient;
    final google = account.provider == 'google.com';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: hero.gradient),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: [
        ListenableBuilder(listenable: store, builder: (context, _) => ProfileAvatar(store: store, size: 64)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (store.profileName.isNotEmpty)
              Text(store.profileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(account.email.isEmpty ? tr('Signed in') : account.email,
                key: const Key('account-email'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: store.profileName.isEmpty ? 1 : 0.8), fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: fg.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (google)
                  const SizedBox(width: 14, height: 14, child: CustomPaint(painter: _GoogleLogoPainter()))
                else
                  Icon(Icons.mail_outline, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(google ? tr('Google account') : tr('Email and password'),
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Signs out after one last save, clears this device and shows the sign-in
/// page. When the last save fails (offline), asks first: changes made since
/// the last save would be lost.
Future<void> signOutAndClear(BuildContext context, {required AccountService account, required SyncService sync}) async {
  final navigator = Navigator.of(context);
  final saved = await sync.saveBeforeSignOut();
  if (!saved && context.mounted) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Some changes are not saved yet')),
        content: Text(tr(
            "BetPilot couldn't reach the server, so your latest changes are only on this device. If you sign out now they are lost. Try again when you're online.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(
            key: const Key('sign-out-anyway'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Sign out anyway')),
          ),
        ],
      ),
    );
    if (go != true) return;
  }
  await sync.signOutAndClear();
  await account.store.setPref(accountSkippedPref, '');
  navigator.popUntil((r) => r.isFirst);
  await navigator.push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => LoginPage(account: account, atLaunch: true)));
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

/// A small reminder, while signed out, that the data only lives on this
/// device and can be lost without an account.
class SignedOutWarning extends StatelessWidget {
  const SignedOutWarning({super.key, required this.onSignIn, required this.onClose});
  final VoidCallback onSignIn;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      key: const Key('signed-out-warning'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: cs.onTertiaryContainer, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Your bets are only saved on this device and could be lost. Sign in to keep them safe.'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const Key('signed-out-warning-sign-in'),
              onPressed: onSignIn,
              style: TextButton.styleFrom(foregroundColor: cs.onTertiaryContainer, visualDensity: VisualDensity.compact),
              child: Text(tr('Sign in'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: tr('Close'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: cs.onTertiaryContainer),
              onPressed: onClose,
            ),
          ]),
        ),
      ),
    );
  }
}
