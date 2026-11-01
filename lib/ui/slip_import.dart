import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/parlay.dart';
import '../data/store.dart';
import '../logic/leg_linker.dart';
import '../logic/slip_reader.dart';
import '../logic/stats.dart';
import '../logic/web_slip_scanner.dart';
import 'bet_form.dart';
import 'parlay_screens.dart';

/// ML Kit's on-device text recognition. Free, no account, and the picture
/// never leaves the phone.
class MlKitSlipScanner implements SlipScanner {
  @override
  Future<List<SlipLine>> scan(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return [
        for (final b in text.blocks)
          for (final l in b.lines)
            SlipLine(
              l.text,
              left: l.boundingBox.left,
              top: l.boundingBox.top,
              right: l.boundingBox.right,
              bottom: l.boundingBox.bottom,
            ),
      ];
    } finally {
      await recognizer.close();
    }
  }
}

/// Where the screenshot and its text come from. Tests swap these.
class SlipImport {
  /// ML Kit on phones; in the web app (iPhone) Tesseract.js in the browser.
  static SlipScanner scanner = kIsWeb ? webSlipScanner() : MlKitSlipScanner();
  static Future<String?> Function() pickImage = () async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.path;
  };
}

/// Pick a bet slip screenshot from any bookmaker, read its selections, let
/// the user check them, then save them as a new parlay and open it.
Future<void> importSlip(BuildContext context, {required BankStore store, required FixturesApi api}) async {
  final read = await _readSlip(context, store: store, api: api, saveLabel: tr('Save as a parlay'));
  if (read == null || !context.mounted) return;
  final (legs, stake) = read;
  final messenger = ScaffoldMessenger.of(context);
  var parlay = await store.newParlay(legs: legs);
  if (stake > 0) parlay = await store.saveParlay(parlay.copyWith(stake: stake));
  messenger.showSnackBar(SnackBar(content: Text(trn(legs.length, 'Parlay saved with {n} selection', 'Parlay saved with {n} selections')), persist: false));
  if (context.mounted) await openParlay(context, store: store, api: api, parlay: parlay);
}

/// Pick a bet slip screenshot, read it and let the user check it, then open
/// the bet form filled in with it: a single bet for one selection, a parlay
/// for more. Nothing is saved until the form is.
Future<void> importBetFromSlip(BuildContext context, {required BankStore store, required FixturesApi api}) async {
  final read = await _readSlip(context, store: store, api: api, saveLabel: tr('Fill in the bet'));
  if (read == null || !context.mounted) return;
  await openBetForm(context, store, template: slipBet(read.$1, read.$2, DateTime.now()), api: api);
}

/// The bet a checked slip becomes: one selection is a single bet, more are a
/// parlay with the combined odds.
Bet slipBet(List<ParlayLeg> legs, double stake, DateTime now) {
  final date = isoDate(now), created = now.toIso8601String();
  if (legs.length > 1) {
    return Parlay(name: '', legs: legs, stake: stake, created: created, updated: created).toBet(date: date, created: created);
  }
  final l = legs.single;
  return Bet(
    selection: l.selection,
    event: l.event,
    sport: l.sport,
    date: date,
    stake: stake,
    odds: l.odds,
    created: created,
    matchId: l.matchId,
    leagueSlug: l.leagueSlug,
    leagueName: l.leagueName,
    kickoff: l.kickoff,
  );
}

/// Picks the screenshot, reads it, shows it to be checked and finds the real
/// matches. Null when the user backs out.
Future<(List<ParlayLeg>, double)?> _readSlip(
  BuildContext context, {
  required BankStore store,
  required FixturesApi api,
  required String saveLabel,
}) async {
  final path = await SlipImport.pickImage();
  if (path == null || !context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text(tr('Reading the slip…'))),
        ],
      ),
    ),
  );
  SlipRead read;
  try {
    read = parseSlip(await SlipImport.scanner.scan(path));
  } catch (e) {
    read = SlipRead(error: '$e');
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();
  final result = await Navigator.of(context).push<(List<ParlayLeg>, double)>(
    MaterialPageRoute(
      builder: (_) => SlipReviewPage(read: read, format: store.settings.oddsFormat, saveLabel: saveLabel),
    ),
  );
  if (result == null || !context.mounted) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text(tr('Finding the matches…')))]),
    ),
  );
  final legs = await linkLegs(api, result.$1);
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();
  return (legs, result.$2);
}

/// The selections read from the slip, editable, before they are saved.
class SlipReviewPage extends StatefulWidget {
  const SlipReviewPage({super.key, required this.read, required this.format, this.saveLabel});
  final SlipRead read;
  final OddsFormat format;

  /// The save button's text; "Save as a parlay" by default.
  final String? saveLabel;

  @override
  State<SlipReviewPage> createState() => _SlipReviewPageState();
}

class _LegFields {
  _LegFields(String selection, String event, String odds)
    : selection = TextEditingController(text: selection),
      event = TextEditingController(text: event),
      odds = TextEditingController(text: odds);
  final TextEditingController selection, event, odds;

  void dispose() {
    selection.dispose();
    event.dispose();
    odds.dispose();
  }
}

class _SlipReviewPageState extends State<SlipReviewPage> {
  late final List<_LegFields> _legs = [
    for (final l in widget.read.legs) _LegFields(l.selection, l.event, formatOdds(l.odds, widget.format)),
  ];
  late final _stake = TextEditingController(
    text: widget.read.stake == null ? '' : widget.read.stake!.toStringAsFixed(widget.read.stake! % 1 == 0 ? 0 : 2),
  );

  @override
  void initState() {
    super.initState();
    if (_legs.isEmpty) _legs.add(_LegFields('', '', ''));
    for (final l in _legs) {
      _listen(l);
    }
    _stake.addListener(() => setState(() {}));
  }

  void _listen(_LegFields l) {
    for (final c in [l.selection, l.event, l.odds]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final l in _legs) {
      l.dispose();
    }
    _stake.dispose();
    super.dispose();
  }

  double? _odds(_LegFields l) => parseOdds(l.odds.text, widget.format);
  bool get _valid => _legs.isNotEmpty && _legs.every((l) => l.selection.text.trim().isNotEmpty && _odds(l) != null);

  void _save() {
    final legs = [
      for (final l in _legs) ParlayLeg(selection: l.selection.text.trim(), event: l.event.text.trim(), odds: _odds(l)!),
    ];
    Navigator.pop(context, (legs, double.tryParse(_stake.text.replaceAll(',', '.')) ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final read = widget.read.legs.length;
    final combined = _legs.fold<double?>(1, (a, l) => a == null || _odds(l) == null ? null : a * _odds(l)!);
    final total = widget.read.totalOdds;
    final mismatch = total != null && combined != null && (combined - total).abs() / total > 0.02;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Check the slip'))),
      body: ListView(
        key: const Key('slip-review'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(read > 0 ? Icons.document_scanner_outlined : Icons.info_outline, color: cs.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    read > 0
                        ? trn(read, 'Read {n} selection from the screenshot. Check each one and fix anything that was misread.', 'Read {n} selections from the screenshot. Check each one and fix anything that was misread.')
                        : widget.read.error != null
                        ? kIsWeb
                        ? tr("The text reader didn't work in this browser ({error}). Add the selections by hand for now.", {'error': widget.read.error})
                        : tr("The text reader didn't work on this phone ({error}). Add the selections by hand for now.", {'error': widget.read.error})
                        : tr("Couldn't read any selections from this picture. Add them by hand, or try a sharper screenshot of the slip."),
                    style: TextStyle(color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          for (final (i, l) in _legs.indexed) ...[
            const SizedBox(height: 12),
            Container(
              key: ObjectKey(l),
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 14),
              decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(tr('Selection {n}', {'n': i + 1}), style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
                      const Spacer(),
                      IconButton(
                        tooltip: tr('Remove'),
                        icon: const Icon(Icons.close),
                        onPressed: _legs.length == 1
                            ? null
                            : () {
                                final gone = _legs[i];
                                setState(() => _legs.removeAt(i));
                                WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
                              },
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: l.selection,
                          decoration: InputDecoration(labelText: tr('Pick')),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: l.event,
                                decoration: InputDecoration(labelText: tr('Match')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: l.odds,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(
                                  labelText: tr('Odds'),
                                  errorText: l.odds.text.isNotEmpty && _odds(l) == null ? tr('Check') : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                final l = _LegFields('', '', '');
                _listen(l);
                _legs.add(l);
              }),
              icon: const Icon(Icons.add),
              label: Text(tr('Add a selection')),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _stake,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Stake (optional)')),
          ),
          const SizedBox(height: 12),
          if (combined != null)
            Text(
              tr('Combined odds {odds}', {'odds': formatOdds(combined, widget.format)}),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('The slip says {odds} in total. Check the prices above.', {'odds': formatOdds(total, widget.format)}),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _valid ? _save : null,
            icon: const Icon(Icons.check),
            label: Text(widget.saveLabel ?? tr('Save as a parlay')),
          ),
        ],
      ),
    );
  }
}
