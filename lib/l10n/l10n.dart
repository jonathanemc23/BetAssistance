import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'es.dart';

export 'picks.dart';

/// The languages the app speaks. English is the source text: every string
/// in the code is English and [tr] looks up its translation.
enum AppLanguage {
  en('English'),
  es('Español');

  const AppLanguage(this.label);

  /// The language's own name, as the language setting lists it.
  final String label;

  static AppLanguage byCode(String? code) => values.where((l) => l.name == code).firstOrNull ?? en;

  /// The phone's language when the app speaks it, else English.
  static AppLanguage get device => byCode(PlatformDispatcher.instance.locale.languageCode);

  Locale get locale => Locale(name);
}

/// The language the app is showing. Set from the saved preference at start
/// and from Settings.
class L10n {
  static AppLanguage _language = AppLanguage.en;
  static AppLanguage get language => _language;
  static bool get spanish => _language == AppLanguage.es;

  /// Switches every [tr] lookup and the date formats to [l]. Money keeps its
  /// usual format in every language.
  static void use(AppLanguage l) {
    _language = l;
    initializeDateFormatting(l == AppLanguage.es ? 'es' : 'en_US');
    Intl.defaultLocale = l == AppLanguage.es ? 'es' : 'en_US';
  }

  /// Builds every widget again, so text from [tr] shows in the new language
  /// on the pages already open.
  static void rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}

/// [en] in the app's language, with each `{name}` replaced from [args].
/// [en] must be a plain string literal so the translation test finds it.
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = L10n.spanish ? (esStrings[en] ?? en) : en;
  if (args.isNotEmpty) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  }
  return s;
}

/// [one] when [n] is 1, else [other], translated; `{n}` is the number.
String trn(num n, String one, String other, [Map<String, Object?> args = const {}]) =>
    tr(n == 1 ? one : other, {'n': n, ...args});
