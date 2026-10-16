import 'package:bank_track/data/models.dart';
import 'package:bank_track/logic/share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const today = '2026-10-17', created = '2026-10-17T10:00:00';
  Bet? decode(String s) => BetLink.decode(s, today: today, created: created);

  final single = Bet(
    selection: 'Arsenal to win',
    event: 'Arsenal vs Chelsea',
    sport: 'Soccer',
    date: '2026-10-01',
    stake: 25,
    odds: 2.1,
    book: 'Bet365',
    status: BetStatus.won,
    notes: 'private',
    created: 'x',
    id: 7,
  );
  final parlay = Bet(
    type: BetType.parlay,
    selection: '3-leg parlay',
    sport: 'Mixed',
    date: '2026-10-01',
    stake: 10,
    odds: 6.27,
    created: 'x',
    status: BetStatus.lost,
    legs: const [
      BetLeg(selection: 'Real Madrid ML', event: 'RMA vs SEV', sport: 'Soccer', odds: 1.5, status: BetStatus.won),
      BetLeg(selection: 'Lakers +4.5', sport: 'Basketball', odds: 1.9, status: BetStatus.lost),
      BetLeg(selection: 'Sinner 2-0 ñ', sport: 'Tennis', odds: 2.2),
    ],
  );

  test('single bet round-trips through every link form, without result or notes', () {
    for (final link in [
      BetLink.webLink(single),
      BetLink.appLink(single),
      BetLink.encode(single),
      BetLink.shareText(single, Settings.defaults()),
    ]) {
      final b = decode(link)!;
      expect(b.selection, 'Arsenal to win');
      expect(b.event, 'Arsenal vs Chelsea');
      expect(b.sport, 'Soccer');
      expect(b.odds, 2.1);
      expect(b.stake, 25);
      expect(b.book, 'Bet365');
      expect(b.status, BetStatus.pending);
      expect(b.notes, '');
      expect(b.id, isNull);
      expect(b.date, today);
    }
  });

  test('links open from the repo-hosted page and from older Pages links', () {
    expect(
      BetLink.webLink(single),
      startsWith('https://raw.githack.com/jonathanemc23/BetAssistance/main/web/b/index.html#'),
    );
    final code = BetLink.encode(single);
    for (final link in [
      'https://jonathanemc23.github.io/BetAssistance/b/#$code',
      'Look at this: https://jonathanemc23.github.io/BetAssistance/b/#$code nice',
      'Try banktrack://bet?d=$code',
    ]) {
      expect(decode(link)?.selection, 'Arsenal to win', reason: link);
    }
  });

  test('parlay keeps its legs and resets their results', () {
    final b = decode(BetLink.webLink(parlay))!;
    expect(b.type, BetType.parlay);
    expect(b.legs.map((l) => l.selection), ['Real Madrid ML', 'Lakers +4.5', 'Sinner 2-0 ñ']);
    expect(b.legs.every((l) => l.status == BetStatus.pending), isTrue);
    expect(b.odds, closeTo(1.5 * 1.9 * 2.2, 1e-9));
    expect(b.selection, '3-leg parlay');
  });

  test('rejects text that is not a bet link', () {
    expect(decode('hello there'), isNull);
    expect(decode('https://example.com/page'), isNull);
    expect(decode('banktrack://bet?d=bm90LWpzb24'), isNull);
    expect(decode(''), isNull);
  });

  test('parlay odds and status rules', () {
    const won = BetLeg(selection: 'a', odds: 2, status: BetStatus.won);
    const voided = BetLeg(selection: 'b', odds: 3, status: BetStatus.voided);
    const lost = BetLeg(selection: 'c', odds: 1.5, status: BetStatus.lost);
    const open = BetLeg(selection: 'd', odds: 1.5);
    expect(parlayOdds([won, voided]), 2);
    expect(parlayStatus([won, voided]), BetStatus.won);
    expect(parlayStatus([won, open]), BetStatus.pending);
    expect(parlayStatus([open, lost]), BetStatus.lost);
    expect(parlayStatus([voided]), BetStatus.voided);
  });
}
