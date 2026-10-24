import 'dart:io';

import 'package:bank_track/l10n/es.dart';
import 'package:bank_track/l10n/l10n.dart';
import 'package:bank_track/logic/assistant.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text passed to tr(), trn() and trc() in lib/, as the key [tr] looks up.
Map<String, String> sourceKeys() {
  const lit = r'''(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")''';
  String text(RegExpMatch m, int g) => (m[g] ?? m[g + 1]!)
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\$', r'$')
      .replaceAll(r'\n', '\n');
  final keys = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('es.dart')) continue;
    final src = f.readAsStringSync();
    for (final m in RegExp(r'\btr\(\s*' + lit).allMatches(src)) {
      keys[text(m, 1)] = f.path;
    }
    for (final m in RegExp(r'''\btrn\([^'"]*?''' + lit + r'\s*,\s*' + lit).allMatches(src)) {
      keys[text(m, 1)] = f.path;
      keys[text(m, 3)] = f.path;
    }
    for (final m in RegExp(r'\btrc\(\s*' + lit + r'\s*,\s*' + lit).allMatches(src)) {
      keys['${text(m, 1)}|${text(m, 3)}'] = f.path;
    }
  }
  return keys;
}

Set<String> placeholders(String s) => {for (final m in RegExp(r'\{(\w+)\}').allMatches(s)) m[1]!};

void main() {
  tearDown(() => L10n.use(AppLanguage.en));

  test('every text in the app has a Spanish translation with the same placeholders', () {
    final keys = sourceKeys();
    expect(keys.length, greaterThan(800));
    final missing = [for (final k in keys.keys) if (!esStrings.containsKey(k)) '${keys[k]}: $k'];
    expect(missing, isEmpty, reason: 'Add these to lib/l10n/es.dart');
    final mismatched = [
      for (final k in keys.keys)
        if (!setEquals(placeholders(k), placeholders(esStrings[k]!))) k,
    ];
    expect(mismatched, isEmpty);
  });

  test('tr, trn and trc follow the language', () {
    expect(tr('Settings'), 'Settings');
    L10n.use(AppLanguage.es);
    expect(tr('Settings'), 'Ajustes');
    expect(trn(1, '{n} pick', '{n} picks'), '1 selección');
    expect(trn(3, '{n} pick', '{n} picks'), '3 selecciones');
    expect(trc('status', 'Open'), 'Abiertas');
    expect(tr('Not a key {x}', {'x': 1}), 'Not a key 1');
    expect(trPick('Over 2.5 goals'), 'Más de 2.5 goles');
    expect(trPick('Everton to win'), 'Gana Everton');
  });

  test('the assistant suggests its questions in Spanish', () {
    L10n.use(AppLanguage.es);
    expect(suggestedQuestions, contains('Tendencia de goles: más de 2.5 y ambos marcan'));
    expect(suggestedQuestions, contains('Últimas noticias'));
  });
}

bool setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
