import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/share.dart';
import 'format.dart';

/// Sheet with the bet's share link: share it to any app, or copy it.
Future<void> showShareBet(BuildContext context, BankStore store, Bet bet) {
  final link = BetLink.webLink(bet);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final theme = Theme.of(c);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Share this bet'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tr('Anyone with ProBets who opens the link gets the same bet ready to log. Your result and notes are not included.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(link, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(tr('Copy link')),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (c.mounted) {
                      Navigator.pop(c);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Link copied'))));
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.share),
                  label: Text(tr('Share')),
                  onPressed: () {
                    Navigator.pop(c);
                    SharePlus.instance.share(ShareParams(
                      text: BetLink.shareText(bet, store.settings),
                      subject: tr('Bet from ProBets'),
                    ));
                  },
                ),
              ),
            ]),
          ]),
        ),
      );
    },
  );
}

/// Dialog to paste a bet link someone sent. Returns the decoded bet.
Future<Bet?> showPasteLink(BuildContext context) async {
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return null;
  return showDialog<Bet>(context: context, builder: (c) => _PasteLinkDialog(initial: clip?.text ?? ''));
}

/// Owns its text controller, so the controller lives until the dialog has
/// finished closing (disposing it as soon as the dialog returned broke the
/// closing animation, which still draws the field).
class _PasteLinkDialog extends StatefulWidget {
  const _PasteLinkDialog({required this.initial});
  final String initial;

  @override
  State<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends State<_PasteLinkDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    final b = BetLink.decode(_ctrl.text, today: isoDate(DateTime.now()), created: DateTime.now().toIso8601String());
    if (b == null) {
      setState(() => _error = tr("That doesn't look like a ProBets bet link"));
    } else {
      Navigator.pop(context, b);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Open a bet link')),
        content: TextField(
          controller: _ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: tr('Paste the link or message'), errorText: _error),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: _open, child: Text(tr('Open'))),
        ],
      );
}

String betTitle(Bet b) => b.isParlay ? tr('{n}-leg parlay', {'n': b.legs.length}) : trPick(b.selection);

String betSubtitle(Bet b) {
  if (b.isParlay) return b.legs.map((l) => trPick(l.selection)).join(' · ');
  return b.event;
}

String betMeta(Bet b, Fmt fmt) => [
      Fmt.date(b.date),
      if (!b.isParlay) sportLabel(b.sport),
      if (b.book.isNotEmpty) b.book,
    ].join(' · ');
