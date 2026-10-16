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

  static BetStatus parse(String v) => v == 'void'
      ? BetStatus.voided
      : BetStatus.values.firstWhere((s) => s.name == v, orElse: () => BetStatus.pending);
}

const sports = [
  'Soccer', 'Basketball', 'American Football', 'Tennis', 'Baseball', 'Ice Hockey',
  'MMA', 'Boxing', 'Cricket', 'Golf', 'Esports', 'Other',
];

const currencies = [
  'USD', 'EUR', 'GBP', 'BRL', 'MXN', 'COP', 'ARS', 'CAD', 'AUD', 'NGN', 'KES', 'ZAR', 'INR', 'JPY',
];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Bet {
  final int? id;
  final String selection;
  final String event;
  final String sport;
  final String date; // yyyy-MM-dd
  final double stake;
  final double odds; // always decimal internally
  final String book;
  final BetStatus status;
  final double? cashout;
  final String notes;
  final String created; // ISO timestamp

  const Bet({
    this.id,
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
  });

  bool get isSettled => status != BetStatus.pending;
  bool get isGraded => status == BetStatus.won || status == BetStatus.lost;

  /// Profit or loss of this bet; zero while pending, push or void.
  double get profit => switch (status) {
        BetStatus.won => stake * (odds - 1),
        BetStatus.lost => -stake,
        BetStatus.cashout => (cashout ?? 0) - stake,
        _ => 0,
      };

  double get potentialProfit => stake * (odds - 1);

  Bet copyWith({BetStatus? status, double? cashout}) => Bet(
        id: id, selection: selection, event: event, sport: sport, date: date, stake: stake,
        odds: odds, book: book, status: status ?? this.status, cashout: cashout ?? this.cashout,
        notes: notes, created: created,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
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

  factory Bet.fromRow(Map<String, Object?> r) => Bet(
        id: r['id'] as int?,
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

  Settings copyWith({String? currency, OddsFormat? oddsFormat, double? startBankroll, String? startDate, double? unit}) =>
      Settings(
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
