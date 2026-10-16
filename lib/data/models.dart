/// Data model shared with the Bank Track web version: bets, bankroll
/// transactions (deposits and withdrawals) and user settings.
library;

enum BetStatus { pending, won, lost, push, voided, cashout }

extension BetStatusX on BetStatus {
  /// Value stored in the database. Kept stable across releases.
  String get dbValue => this == BetStatus.voided ? 'void' : name;

  String get label => switch (this) {
    BetStatus.pending => 'Pending',
    BetStatus.won => 'Won',
    BetStatus.lost => 'Lost',
    BetStatus.push => 'Push',
    BetStatus.voided => 'Void',
    BetStatus.cashout => 'Cashed out',
  };

  static BetStatus parse(String v) =>
      v == 'void' ? BetStatus.voided : BetStatus.values.firstWhere((s) => s.name == v, orElse: () => BetStatus.pending);
}

const sports = [
  'Soccer',
  'Basketball',
  'American Football',
  'Tennis',
  'Baseball',
  'Ice Hockey',
  'MMA',
  'Boxing',
  'Cricket',
  'Golf',
  'Esports',
  'Other',
];

const currencies = ['USD', 'EUR', 'GBP', 'BRL', 'MXN', 'COP', 'ARS', 'CAD', 'AUD', 'NGN', 'KES', 'ZAR', 'INR', 'JPY'];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum BetType { single, parlay, system, other }

extension BetTypeX on BetType {
  String get label => switch (this) {
    BetType.single => 'Single',
    BetType.parlay => 'Parlay',
    BetType.system => 'System',
    BetType.other => 'Other',
  };

  static BetType parse(String? v) => BetType.values.firstWhere((t) => t.name == v, orElse: () => BetType.single);
}

/// One selection inside a parlay.
class BetLeg {
  final String selection;
  final String event;
  final String sport;
  final double odds;
  final BetStatus status;

  const BetLeg({
    required this.selection,
    this.event = '',
    this.sport = 'Other',
    required this.odds,
    this.status = BetStatus.pending,
  });

  BetLeg copyWith({String? selection, String? event, String? sport, double? odds, BetStatus? status}) => BetLeg(
    selection: selection ?? this.selection,
    event: event ?? this.event,
    sport: sport ?? this.sport,
    odds: odds ?? this.odds,
    status: status ?? this.status,
  );

  Map<String, Object?> toRow(int betId, int position) => {
    'bet_id': betId,
    'position': position,
    'selection': selection,
    'event': event,
    'sport': sport,
    'odds': odds,
    'status': status.dbValue,
  };

  factory BetLeg.fromRow(Map<String, Object?> r) => BetLeg(
    selection: (r['selection'] as String?) ?? '',
    event: (r['event'] as String?) ?? '',
    sport: (r['sport'] as String?) ?? 'Other',
    odds: (r['odds'] as num).toDouble(),
    status: BetStatusX.parse((r['status'] as String?) ?? 'pending'),
  );
}

/// Parlay rules: odds multiply; a void (or push) leg drops out at odds 1.0;
/// one lost leg loses the parlay; every leg won or void wins it.
double parlayOdds(List<BetLeg> legs) =>
    legs.where((l) => l.status != BetStatus.voided && l.status != BetStatus.push).fold(1.0, (a, l) => a * l.odds);

BetStatus parlayStatus(List<BetLeg> legs) {
  if (legs.isEmpty) return BetStatus.pending;
  if (legs.any((l) => l.status == BetStatus.lost)) return BetStatus.lost;
  if (legs.any((l) => l.status == BetStatus.pending)) return BetStatus.pending;
  final live = legs.where((l) => l.status != BetStatus.voided && l.status != BetStatus.push);
  return live.isEmpty ? BetStatus.voided : BetStatus.won;
}

class Bet {
  final int? id;
  final BetType type;
  final String selection;
  final String event;
  final String sport;
  final String date; // yyyy-MM-dd
  final double stake;
  final double odds; // always decimal internally; for a parlay, the combined odds
  final String book;
  final BetStatus status;
  final double? cashout;
  final String notes;
  final String created; // ISO timestamp
  final List<BetLeg> legs; // parlay legs, empty for other types

  const Bet({
    this.id,
    this.type = BetType.single,
    required this.selection,
    this.event = '',
    this.sport = 'Other',
    required this.date,
    required this.stake,
    required this.odds,
    this.book = '',
    this.status = BetStatus.pending,
    this.cashout,
    this.notes = '',
    required this.created,
    this.legs = const [],
  });

  bool get isSettled => status != BetStatus.pending;
  bool get isGraded => status == BetStatus.won || status == BetStatus.lost;
  bool get isParlay => type == BetType.parlay;

  /// Profit or loss of this bet; zero while pending, push or void.
  double get profit => switch (status) {
    BetStatus.won => stake * (odds - 1),
    BetStatus.lost => -stake,
    BetStatus.cashout => (cashout ?? 0) - stake,
    _ => 0,
  };

  double get potentialProfit => stake * (odds - 1);

  Bet copyWith({int? id, BetStatus? status, double? cashout, String? date, String? created, double? stake}) => Bet(
    id: id ?? this.id,
    type: type,
    selection: selection,
    event: event,
    sport: sport,
    date: date ?? this.date,
    stake: stake ?? this.stake,
    odds: odds,
    book: book,
    status: status ?? this.status,
    cashout: cashout ?? this.cashout,
    notes: notes,
    created: created ?? this.created,
    legs: legs,
  );

  /// Same bet without an id or result, ready to be logged again.
  Bet asNew({required String date, required String created}) => Bet(
    type: type,
    selection: selection,
    event: event,
    sport: sport,
    date: date,
    stake: stake,
    odds: odds,
    book: book,
    created: created,
    legs: [for (final l in legs) l.copyWith(status: BetStatus.pending)],
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'bet_type': type.name,
    'selection': selection,
    'event': event,
    'sport': sport,
    'date': date,
    'stake': stake,
    'odds': odds,
    'book': book,
    'status': status.dbValue,
    'cashout': cashout,
    'notes': notes,
    'created': created,
  };

  factory Bet.fromRow(Map<String, Object?> r, [List<BetLeg> legs = const []]) => Bet(
    id: r['id'] as int?,
    type: BetTypeX.parse(r['bet_type'] as String?),
    selection: (r['selection'] as String?) ?? '',
    event: (r['event'] as String?) ?? '',
    sport: (r['sport'] as String?) ?? 'Other',
    date: r['date'] as String,
    stake: (r['stake'] as num).toDouble(),
    odds: (r['odds'] as num).toDouble(),
    book: (r['book'] as String?) ?? '',
    status: BetStatusX.parse((r['status'] as String?) ?? 'pending'),
    cashout: (r['cashout'] as num?)?.toDouble(),
    notes: (r['notes'] as String?) ?? '',
    created: (r['created'] as String?) ?? '',
    legs: legs,
  );
}

enum TxKind { deposit, withdrawal }

class BankTx {
  final int? id;
  final TxKind kind;
  final double amount;
  final String date;
  final String note;

  const BankTx({this.id, required this.kind, required this.amount, required this.date, this.note = ''});

  /// Signed effect on the bankroll.
  double get signed => kind == TxKind.deposit ? amount : -amount;

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'kind': kind.name,
    'amount': amount,
    'date': date,
    'note': note,
  };

  factory BankTx.fromRow(Map<String, Object?> r) => BankTx(
    id: r['id'] as int?,
    kind: r['kind'] == 'withdrawal' ? TxKind.withdrawal : TxKind.deposit,
    amount: (r['amount'] as num).toDouble(),
    date: r['date'] as String,
    note: (r['note'] as String?) ?? '',
  );
}

enum OddsFormat { decimal, american }

class Settings {
  final String currency;
  final OddsFormat oddsFormat;
  final double startBankroll;
  final String startDate;
  final double unit;

  const Settings({
    this.currency = 'USD',
    this.oddsFormat = OddsFormat.decimal,
    this.startBankroll = 1000,
    required this.startDate,
    this.unit = 10,
  });

  factory Settings.defaults() => Settings(startDate: isoDate(DateTime.now()));

  Settings copyWith({
    String? currency,
    OddsFormat? oddsFormat,
    double? startBankroll,
    String? startDate,
    double? unit,
  }) => Settings(
    currency: currency ?? this.currency,
    oddsFormat: oddsFormat ?? this.oddsFormat,
    startBankroll: startBankroll ?? this.startBankroll,
    startDate: startDate ?? this.startDate,
    unit: unit ?? this.unit,
  );

  Map<String, String> toMap() => {
    'currency': currency,
    'oddsFormat': oddsFormat.name,
    'startBankroll': startBankroll.toString(),
    'startDate': startDate,
    'unit': unit.toString(),
  };

  factory Settings.fromMap(Map<String, String> m) {
    final d = Settings.defaults();
    return Settings(
      currency: m['currency'] ?? d.currency,
      oddsFormat: m['oddsFormat'] == 'american' ? OddsFormat.american : OddsFormat.decimal,
      startBankroll: double.tryParse(m['startBankroll'] ?? '') ?? d.startBankroll,
      startDate: m['startDate'] ?? d.startDate,
      unit: double.tryParse(m['unit'] ?? '') ?? d.unit,
    );
  }
}
