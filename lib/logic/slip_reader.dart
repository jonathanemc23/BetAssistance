import 'markets.dart';

/// One line of text read from a bet slip screenshot, with where it sits on
/// the image (pixels, origin top left).
class SlipLine {
  const SlipLine(this.text, {this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});
  final String text;
  final double left, top, right, bottom;

  double get middle => (top + bottom) / 2;
  double get height => bottom - top;
}

/// A selection read from a slip. Any field can be wrong; the user checks
/// them before the parlay is saved.
class SlipLeg {
  const SlipLeg({required this.selection, this.event = '', this.market = '', required this.odds, this.date});
  final String selection;
  final String event;

  /// The kick-off the slip shows for the match ("18/10/2026, 08:00",
  /// "Hoy 18:00"), in the phone's time. Null when it shows none.
  final DateTime? date;

  /// One of the [markets] ids, from the slip's market text or the selection.
  final String market;
  final double odds; // decimal
}

class SlipRead {
  const SlipRead({this.legs = const [], this.stake, this.totalOdds, this.error});
  final List<SlipLeg> legs;
  final double? stake;
  final double? totalOdds;

  /// Why the text reader failed, when it did (shown so it can be reported).
  final String? error;
}

/// Which words of one OCR line to keep, as indexes: drops what the reader
/// wasn't sure of (team crests and sport icons read as "(e)" or "8)") and
/// symbols left at either end ("® Cruz Azul").
List<int> tidyWords(List<(String, double)> words) {
  final keep = [
    for (final (i, (text, confidence)) in words.indexed)
      if (text.isNotEmpty && confidence >= 50) i,
  ];
  bool symbol(int i) => !RegExp(r'[A-Za-zÀ-ÿ0-9]').hasMatch(words[i].$1);
  while (keep.isNotEmpty && symbol(keep.first)) {
    keep.removeAt(0);
  }
  while (keep.isNotEmpty && symbol(keep.last)) {
    keep.removeLast();
  }
  return keep;
}

/// Reads the text of a bet slip screenshot. On the phone this is ML Kit's
/// on-device text recognition; tests use a fake.
abstract class SlipScanner {
  Future<List<SlipLine>> scan(String imagePath);
}

/// Turns the lines of any bookmaker's bet slip into selections. Slips differ,
/// but each selection has a price on its own row, a pick next to or above
/// it, and usually the match ("A v B", "A - B", "A vs B") and the market
/// close by. Rows about the stake, returns and totals are kept apart.
SlipRead parseSlip(List<SlipLine> lines, {DateTime? now}) {
  final rows = _rows(lines);
  if (rows.isEmpty) return const SlipRead();
  final today = now ?? DateTime.now();
  final dates = [for (final r in rows) slipDate(r.join(' '), today)];

  double? stake, total;
  final kinds = <_Kind>[];
  final prices = <double?>[];
  final rest = <String>[];
  for (var r in rows) {
    // A live score at the right of a team's row ("Arsenal ... 1").
    if (r.length > 1 && RegExp(r'^\d{1,2}$').hasMatch(r.last.trim())) r = r.sublist(0, r.length - 1);
    var text = r.join(' ');
    final lower = _plain(text);
    if (_noise.hasMatch(lower)) {
      // "Combinada de 6  $60.000   23.61": the heading carries the total odds.
      final head = _price(r.last);
      if (head != null && _parlayHead.hasMatch(lower)) total ??= head;
      if (head == null || _parlayHead.hasMatch(lower)) {
        kinds.add(_Kind.noise);
        prices.add(null);
        rest.add('');
        continue;
      }
    }
    if (_isMoneyRow(lower)) {
      if (_stakeWords.hasMatch(lower) && !_returnWords.hasMatch(lower)) stake ??= _amount(text);
      if (_totalOddsWords.hasMatch(lower)) total ??= _price(r.last) ?? _trailingPrice(text)?.$2;
      kinds.add(_Kind.noise);
      prices.add(null);
      rest.add('');
      continue;
    }
    // A price on its own at the right, or at the end of the row's text.
    final last = r.length > 1 ? _price(r.last) : null;
    final (before, price) = last != null
        ? (r.sublist(0, r.length - 1).join(' '), last)
        : (_trailingPrice(text) ?? (text, null));
    final only = _price(text);
    if (only != null) {
      kinds.add(_Kind.price);
      prices.add(only);
      rest.add('');
    } else if (price != null) {
      kinds.add(_Kind.price);
      prices.add(price);
      rest.add(_clean(before));
    } else {
      text = _withoutDates(text);
      kinds.add(
        _noise.hasMatch(lower) || _clean(text).isEmpty
            ? _Kind.noise
            : _isEvent(text)
            ? _Kind.event
            : _isMarket(lower)
            ? _Kind.market
            : _Kind.text,
      );
      prices.add(null);
      rest.add(_clean(text));
    }
  }

  final priceRows = [
    for (var i = 0; i < kinds.length; i++)
      if (kinds[i] == _Kind.price) i,
  ];
  if (priceRows.isEmpty) return SlipRead(stake: stake, totalOdds: total);

  // Does the match come before the price (the leg's block ends with the
  // price) or after it (the block starts with it)? Judge by the first leg.
  final firstEvent = kinds.indexOf(_Kind.event);
  final eventFirst = firstEvent >= 0 && firstEvent < priceRows.first;

  final legs = <SlipLeg>[];
  for (var n = 0; n < priceRows.length; n++) {
    final p = priceRows[n];
    final from = eventFirst ? (n == 0 ? 0 : priceRows[n - 1] + 1) : p + 1;
    final to = eventFirst ? p : (n + 1 < priceRows.length ? priceRows[n + 1] : kinds.length);
    final block = [
      for (var i = from; i < to; i++)
        if (kinds[i] != _Kind.noise && kinds[i] != _Kind.price) i,
    ];

    DateTime? date;
    for (var i = from; i < to && date == null; i++) {
      date = dates[i];
    }
    String? event, market;
    final texts = <String>[];
    for (final i in block) {
      switch (kinds[i]) {
        case _Kind.event:
          event ??= rest[i];
        case _Kind.market:
          market ??= rest[i];
        default:
          texts.add(rest[i]);
      }
    }
    // The pick: next to the price, else the text row nearest to it.
    var selection = rest[p];
    if (selection.isEmpty && texts.isNotEmpty) selection = eventFirst ? texts.removeLast() : texts.removeAt(0);
    if (selection.isEmpty && market != null) {
      selection = market;
      market = null;
    }
    if (selection.isEmpty) continue;
    // No "A v B" line: many slips list the two teams one under the other.
    if (event == null && texts.length == 2) event = '${texts[0]} vs ${texts[1]}';
    // A bare team or answer means little without its market ("Sí" for both
    // teams to score, "Como 1907" for win or lead by two).
    if (market != null && !_isPlainResult(market) && !_saysItAll.hasMatch(_plain(selection))) {
      selection = '$selection · $market';
    }
    legs.add(SlipLeg(selection: selection, event: event ?? '', market: _marketId(market, selection), odds: prices[p]!, date: date));
  }
  return SlipRead(legs: legs, stake: stake, totalOdds: total);
}

/// The kick-off date written in [text], if any: "18/10/2026, 08:00",
/// "18/10 20:00", "Hoy 18:00", "Tomorrow 15:30". Day first unless that
/// can't be a date ("10/18/2026"). With no year, the one nearest [now].
DateTime? slipDate(String text, DateTime now) {
  final lower = _plain(text);
  final time = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(lower);
  final h = time == null ? 0 : int.parse(time.group(1)!), min = time == null ? 0 : int.parse(time.group(2)!);
  if (h > 23 || min > 59) return null;
  final rel = RegExp(r'^(hoy|today|manana|tomorrow|ayer|yesterday)\b').firstMatch(lower.trim());
  if (rel != null) {
    final shift = switch (rel.group(1)) { 'manana' || 'tomorrow' => 1, 'ayer' || 'yesterday' => -1, _ => 0 };
    return DateTime(now.year, now.month, now.day + shift, h, min);
  }
  final d = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b').firstMatch(lower);
  if (d == null) return null;
  // Without a year or a time it may be a price, a line or a score ("2.5", "2-1").
  if (d.group(3) == null && time == null) return null;
  final a = int.parse(d.group(1)!), b = int.parse(d.group(2)!);
  var (day, month) = (a, b);
  if (month > 12 && day <= 12) (day, month) = (b, a);
  if (day < 1 || day > 31 || month < 1 || month > 12) return null;
  DateTime at(int y) => DateTime(y, month, day, h, min);
  final y = d.group(3);
  if (y != null) {
    final year = y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
    final out = at(year);
    return out.month == month ? out : null;
  }
  final options = [at(now.year - 1), at(now.year), at(now.year + 1)].where((t) => t.month == month);
  if (options.isEmpty) return null;
  return options.reduce((x, y) => x.difference(now).abs() <= y.difference(now).abs() ? x : y);
}

enum _Kind { price, event, market, text, noise }

/// Groups OCR lines into rows (lines whose middles sit at the same height),
/// each row's pieces left to right, rows top to bottom.
List<List<String>> _rows(List<SlipLine> lines) {
  final sorted = [...lines.where((l) => l.text.trim().isNotEmpty)]..sort((a, b) => a.middle.compareTo(b.middle));
  final rows = <List<SlipLine>>[];
  for (final l in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    final tol = (l.height > 0 ? l.height : 10) * 0.5;
    if (row != null && (row.first.middle - l.middle).abs() <= tol) {
      row.add(l);
    } else {
      rows.add([l]);
    }
  }
  return [
    for (final r in rows) [for (final l in (r..sort((a, b) => a.left.compareTo(b.left)))) l.text.trim()],
  ];
}

/// A price on its own: 1.85, 1,85, @2.10, +150, -110, 5/2.
double? _price(String s) {
  final t = s.trim().replaceAll('−', '-').replaceFirst(RegExp(r'^@\s*'), '');
  final dec = RegExp(r'^\d{1,3}[.,]\d{2}$').firstMatch(t);
  if (dec != null) {
    final v = double.parse(t.replaceAll(',', '.'));
    return v > 1 && v <= 1000 ? v : null;
  }
  final us = RegExp(r'^[+-](\d{3,5})$').firstMatch(t);
  if (us != null) {
    final n = double.parse(us.group(1)!);
    if (n < 100) return null;
    return t.startsWith('+') ? 1 + n / 100 : 1 + 100 / n;
  }
  final frac = RegExp(r'^(\d{1,3})/(\d{1,3})$').firstMatch(t);
  if (frac != null) {
    final a = double.parse(frac.group(1)!), b = double.parse(frac.group(2)!);
    return b == 0 ? null : 1 + a / b;
  }
  return null;
}

/// "Arsenal 1.85" or "Arsenal @ 1.85": the text and the price at its end.
(String, double?)? _trailingPrice(String s) {
  final m = RegExp(r'^(.*\S)\s+@?\s*([+\-−]?\d[\d.,/]*)$').firstMatch(s.trim());
  if (m == null) return null;
  final p = _price(m.group(2)!);
  // "Over 2.5" and lines like it are picks, not prices.
  if (p == null || RegExp(r'\b(over|under|mas de|menos de|más de|o|u)$', caseSensitive: false).hasMatch(m.group(1)!)) {
    return null;
  }
  return (m.group(1)!, p);
}

/// A money amount: "$ 10.000" (Colombian pesos), "10,000.50", "€5,00", "20".
double? _amount(String s) {
  final nums = RegExp(r'\d[\d.,]*').allMatches(s).map((m) => m.group(0)!).toList();
  if (nums.isEmpty) return null;
  var t = nums.last;
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    t = t.replaceAll(RegExp(r'[.,]'), '');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+,\d{1,2}$').hasMatch(t)) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', t.contains('.') ? '' : '.');
  }
  return double.tryParse(t);
}

String _plain(String s) {
  const acc = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n', 'ü': 'u', 'ç': 'c', 'ã': 'a', 'õ': 'o', 'ø': 'o', 'å': 'a'};
  return s.toLowerCase().split('').map((c) => acc[c] ?? c).join();
}

/// Dates and kick-off times next to the teams ("18/10/2026, 08:00").
String _withoutDates(String s) => s
    .replaceAll(RegExp(r'\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?,?(\s*\d{1,2}:\d{2})?'), ' ')
    .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ')
    .trim();

/// A live match's clock: "03'", "45+2'", "90’".
final _clock = RegExp(r"\b\d{1,3}(\+\d{1,2})?\s?['’´`]");

String _clean(String s) => s
    .replaceAll(_clock, ' ')
    // A team crest read as a stray letter or two before the name: "Y Brondby
    // IF", "rc Midtjylland".
    .replaceAll(RegExp(r'^([a-z]{1,2}|[A-Z])\s+(?=[A-ZÀ-Ý])'), '')
    .replaceAll(RegExp(r'^[\s•·✓✔☑○●◉▪■□x×*>-]+(?=\S)'), '')
    .replaceAll(RegExp(r'^[?+©®]\s*(?=[A-Za-zÀ-ÿ])'), '')
    .replaceAll(RegExp(r'\s*[✓✔☑✅]+\s*$'), '')
    .replaceAll(RegExp(r'\s+@\s*$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final _parlayHead = RegExp(
  r'^(combinada|parlay|parley|multiple|múltiple|acca|accumulator|apuesta multiple|apuesta combinada|'
  r'(doble|triple|cuadruple|cuádruple|double|treble)(?=\s*[\d.,]*$))',
);

bool _isPlainResult(String market) => RegExp(
  r'^(1x2|match result|resultado|resultado del partido|ganador del encuentro|full time result|tiempo reglamentario|ganador del partido|money ?line|1x2 tiempo reglamentario|resultado final)$',
).hasMatch(_plain(market).trim());

/// Picks that already name their market: lines, double chance, over/under.
final _saysItAll = RegExp(r'\d[.,]\d|\b(o|or|empate|draw|over|under|mas|menos|y|and|to win|to score)\b|[+-]\d');

final _stakeWords = RegExp(r'\b(stake|apuesta|apostado|importe|monto|valor|wager|bet amount|risk|riesgo|stk)\b');
final _returnWords = RegExp(
  r'(\breturns?\b|retorno|ganancia|premio|\bpago\b|payout|^to win\b|para ganar|posible|potential|\bcobro\b)',
);
final _totalOddsWords = RegExp(
  r'(total odds|cuota total|cuotas totales|odds total|combined odds|cuota combinada|momio)',
);

bool _isMoneyRow(String lower) =>
    _stakeWords.hasMatch(lower) ||
    _returnWords.hasMatch(lower) ||
    _totalOddsWords.hasMatch(lower) ||
    RegExp(r'(cash ?out|\bcobrar\b|\bsaldo\b|\bbalance\b|\bbono\b|\bbonus\b|freebet|apuesta gratis|^total\s*[:$€£\d])')
        .hasMatch(lower) ||
    RegExp(r'([$€£]|\bcop\b|\busd\b|\beur\b|\bmxn\b|\bs/)\s*\d').hasMatch(lower);

/// Rows that are slip chrome: headings, buttons, dates and ids.
final _noise = RegExp(
  r'^(bet ?slip|boleto|cupon|cupón|mis apuestas|my bets|parlay|parley|combinada|multiple|múltiple|acca|accumulator|'
  r'apuesta multiple|apuesta combinada|(doble|triple|cuadruple|cuádruple|double|treble)(?=\s*[\d.,]*$)|\d+ (selecciones|selections|legs|picks|fold)|singles?|sencillas?|'
  r'en vivo|live|abiertas|open|settled|liquidadas|place bet|realizar apuesta|apostar|share|compartir|'
  r'id[: ]|ref[: ]|ticket|hoy|today|tomorrow|manana|mañana)(\b|$)|^[\d\s:/.-]+$|'
  // A live match's clock and score beside the teams: "03'", "45+2' 1", "HT".
  r"^\d{1,3}(\+\d{1,2})?\s?['’´`](\s*\d{1,2})?$|^(ht|ft|descanso|entretiempo|half ?time|en juego)$",
  caseSensitive: false,
);

bool _isEvent(String s) {
  final m = RegExp(
    r'^(.*[a-zA-ZÀ-ÿ].*?)\s+(vs\.?|v|-|–|x|@|vs)\s+(.*[a-zA-ZÀ-ÿ].*)$',
    caseSensitive: false,
  ).firstMatch(s.trim());
  if (m == null) return false;
  // "Over 2.5 - goals" and "Handicap -1" are not matches.
  return !RegExp(r'^(over|under|mas|más|menos|handicap|total)\b', caseSensitive: false).hasMatch(m.group(1)!.trim());
}

final _marketWords = RegExp(
  r'(match result|full time|result|resultado|ganador|1x2|money ?line|moneyline|winner|tiempo reglamentario|'
  r'double chance|doble oportunidad|draw no bet|empate no|apuesta sin empate|handicap|hándicap|spread|'
  r'total goals|total de goles|goles|goals|over/under|mas/menos|más/menos|both teams|ambos equipos|btts|'
  r'corner|córner|tiros de esquina|cards|tarjetas|half|mitad|medio tiempo|descanso|correct score|marcador|'
  r'goleador|scorer|anotador|to score|marcar|ganar el partido|liderar|lead by)',
);

bool _isMarket(String lower) => _marketWords.hasMatch(lower) && lower.split(' ').length <= 9;

String _marketId(String? market, String selection) {
  final fromSelection = marketOf(selection);
  if (market == null) return fromSelection;
  final m = _plain(market);
  if (RegExp(r'corner|esquina').hasMatch(m)) return 'corners';
  if (RegExp(r'card|tarjeta').hasMatch(m)) return 'cards';
  if (RegExp(r'both teams|ambos|btts').hasMatch(m)) return 'btts';
  if (RegExp(r'handicap|spread').hasMatch(m)) return 'handicap';
  if (RegExp(r'double chance|doble oportunidad').hasMatch(m)) return 'double_chance';
  if (RegExp(r'draw no bet|empate no|sin empate').hasMatch(m)) return 'dnb';
  if (RegExp(r'correct score|marcador').hasMatch(m)) return 'correct_score';
  if (RegExp(r'scorer|goleador|anotador|to score|marcar').hasMatch(m)) return 'scorer';
  if (RegExp(r'half|mitad|medio tiempo|descanso').hasMatch(m)) return 'half_time';
  if (RegExp(r'liderar|lead by|early payout|pago anticipado').hasMatch(m)) return 'other';
  if (RegExp(r'goal|goles|total|over|mas/menos').hasMatch(m)) return 'goals';
  if (RegExp(r'result|ganador|1x2|money|winner|reglamentario').hasMatch(m)) return 'result';
  return fromSelection;
}
