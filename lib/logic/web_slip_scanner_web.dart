import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'slip_reader.dart';

/// Tesseract.js, pinned. Its worker, engine and language data come from the
/// same CDN on first use and are cached by the browser after that.
const _script = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';

/// Latin text: English and Spanish cover the slips of most betting sites.
const _languages = 'eng+spa';

Future<void>? _loading;

Future<void> _load() {
  if (globalContext.has('Tesseract')) return Future.value();
  return _loading ??= () {
    final done = Completer<void>();
    final s = web.HTMLScriptElement()
      ..src = _script
      ..async = true;
    s.onload = ((web.Event _) => done.complete()).toJS;
    s.onerror = ((web.Event _) {
      _loading = null;
      done.completeError(StateError("couldn't load the text reader, check the connection"));
    }).toJS;
    web.document.head!.append(s);
    return done.future;
  }();
}

class TesseractSlipScanner implements SlipScanner {
  JSObject? _worker;

  Future<JSObject> _ready() async {
    await _load();
    if (_worker != null) return _worker!;
    final tesseract = globalContext['Tesseract'] as JSObject;
    final w = await (tesseract.callMethod<JSPromise<JSObject>>('createWorker'.toJS, _languages.toJS)).toDart;
    // Sparse text: slips are short pieces spread over the screen (pick on the
    // left, price on the right, date in between). The default single-block
    // mode runs them together and misreads team crests as letters.
    await w.callMethod<JSPromise<JSAny?>>('setParameters'.toJS, {'tessedit_pageseg_mode': '11'}.jsify()).toDart;
    return _worker = w;
  }

  /// [imagePath] is the picked file's blob URL.
  @override
  Future<List<SlipLine>> scan(String imagePath) async {
    final worker = await _ready();
    final result = await worker.callMethod<JSPromise<JSObject>>('recognize'.toJS, imagePath.toJS).toDart;
    final data = result['data'] as JSObject;
    final lines = <SlipLine>[];
    void add(JSObject l) {
      final words = [
        for (final w in ((l['words'] as JSArray<JSObject>?)?.toDart ?? const <JSObject>[]))
          (
            text: (w['text'] as JSString?)?.toDart.trim() ?? '',
            confidence: (w['confidence'] as JSNumber?)?.toDartDouble ?? 0,
            box: w['bbox'] as JSObject,
          ),
      ];
      final kept = tidyWords([for (final w in words) (w.text, w.confidence)]);
      if (kept.isEmpty) return;
      double n(JSObject box, String k) => (box[k] as JSNumber).toDartDouble;
      final boxes = [for (final i in kept) words[i].box];
      lines.add(SlipLine(
        [for (final i in kept) words[i].text].join(' '),
        left: boxes.map((b) => n(b, 'x0')).reduce((a, b) => a < b ? a : b),
        top: boxes.map((b) => n(b, 'y0')).reduce((a, b) => a < b ? a : b),
        right: boxes.map((b) => n(b, 'x1')).reduce((a, b) => a > b ? a : b),
        bottom: boxes.map((b) => n(b, 'y1')).reduce((a, b) => a > b ? a : b),
      ));
    }

    // Tesseract.js 5 lists the lines; later versions nest them in blocks.
    final flat = data['lines'];
    if (flat != null && flat.isA<JSArray>()) {
      for (final l in (flat as JSArray<JSObject>).toDart) {
        add(l);
      }
    } else {
      final blocks = data['blocks'];
      if (blocks != null && blocks.isA<JSArray>()) {
        for (final b in (blocks as JSArray<JSObject>).toDart) {
          for (final p in (b['paragraphs'] as JSArray<JSObject>).toDart) {
            for (final l in (p['lines'] as JSArray<JSObject>).toDart) {
              add(l);
            }
          }
        }
      }
    }
    return lines;
  }
}
