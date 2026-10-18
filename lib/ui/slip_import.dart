import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../data/fixtures.dart';
import '../data/models.dart';
import '../data/parlay.dart';
import '../data/store.dart';
import '../logic/slip_reader.dart';
import '../logic/stats.dart';
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
  static SlipScanner scanner = MlKitSlipScanner();
  static Future<String?> Function() pickImage = () async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.path;
  };
}

/// Pick a bet slip screenshot from any bookmaker, read its selections, let
/// the user check them, then save them as a new parlay and open it.
Future<void> importSlip(BuildContext context, {required BankStore store, required FixturesApi api}) async {
  final path = await SlipImport.pickImage();
  if (path == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Reading the slip…')),
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
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  final result = await Navigator.of(context).push<(List<ParlayLeg>, double)>(
    MaterialPageRoute(
      builder: (_) => SlipReviewPage(read: read, format: store.settings.oddsFormat),
    ),
  );
  if (result == null || !context.mounted) return;
  var parlay = await store.newParlay(legs: result.$1);
  if (result.$2 > 0) parlay = await store.saveParlay(parlay.copyWith(stake: result.$2));
  messenger.showSnackBar(SnackBar(content: Text('Parlay saved with ${result.$1.length} selections'), persist: false));
  if (context.mounted) await openParlay(context, store: store, api: api, parlay: parlay);
}

/// The selections read from the slip, editable, before they are saved.
class SlipReviewPage extends StatefulWidget {
  const SlipReviewPage({super.key, required this.read, required this.format});
  final SlipRead read;
  final OddsFormat format;

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
      appBar: AppBar(title: const Text('Check the slip')),
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
                        ? 'Read $read selection${read == 1 ? '' : 's'} from the screenshot. Check each one and fix anything that was misread.'
                        : widget.read.error != null
                        ? "The text reader didn't work on this phone (${widget.read.error}). Add the selections by hand for now."
                        : "Couldn't read any selections from this picture. Add them by hand, or try a sharper screenshot of the slip.",
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
                      Text('Selection ${i + 1}', style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Remove',
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
                          decoration: const InputDecoration(labelText: 'Pick'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: l.event,
                                decoration: const InputDecoration(labelText: 'Match'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: l.odds,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                decoration: InputDecoration(
                                  labelText: 'Odds',
                                  errorText: l.odds.text.isNotEmpty && _odds(l) == null ? 'Check' : null,
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
              label: const Text('Add a selection'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _stake,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Stake (optional)'),
          ),
          const SizedBox(height: 12),
          if (combined != null)
            Text(
              'Combined odds ${formatOdds(combined, widget.format)}',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'The slip says ${formatOdds(total, widget.format)} in total. Check the prices above.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _valid ? _save : null,
            icon: const Icon(Icons.check),
            label: const Text('Save as a parlay'),
          ),
        ],
      ),
    );
  }
}
