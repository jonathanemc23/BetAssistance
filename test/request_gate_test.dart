import 'dart:async';

import 'package:bank_track/data/request_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs a few at a time, urgent ones first', () async {
    final gate = RequestGate(2);
    var running = 0, most = 0;
    final order = <String>[];
    final release = Completer<void>();
    Future<void> job(String name, {bool urgent = false}) => gate.run(urgent: urgent, () async {
      running++;
      most = running > most ? running : most;
      order.add(name);
      await release.future;
      running--;
    });
    final all = [for (var i = 0; i < 5; i++) job('bg$i'), job('screen', urgent: true)];
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await Future.wait(all);
    expect(most, 2);
    expect(order.take(3), ['bg0', 'bg1', 'screen']);
    expect(order, hasLength(6));
  });

  test('a background request past the per-minute limit is skipped, an urgent one is not', () async {
    final gate = RequestGate(3, perMinute: 8);
    final ran = <int>[];
    var skipped = 0;
    await Future.wait([
      for (var i = 0; i < 6; i++)
        gate.run(() async => ran.add(i)).catchError((Object e) {
          if (e is GateFull) skipped++;
        }),
    ]);
    // Five of eight are kept for what's on screen.
    expect((ran.length, skipped), (3, 3));
    await gate.run(urgent: true, () async => ran.add(99));
    expect(ran.last, 99);
  });

  test('a pause skips background requests and holds urgent ones until it ends', () async {
    final gate = RequestGate(2, perMinute: 25);
    gate.pause(const Duration(milliseconds: 80));
    expect(gate.run(() async => 1), throwsA(isA<GateFull>()));
    final watch = Stopwatch()..start();
    expect(await gate.run(urgent: true, () async => 2), 2);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(70));
  });

  test('slots kept for urgent requests stay free of background ones', () async {
    final gate = RequestGate(3, urgentSlots: 1);
    final release = Completer<void>();
    var running = 0;
    final background = [for (var i = 0; i < 4; i++) gate.run(() async { running++; await release.future; })];
    await Future<void>.delayed(Duration.zero);
    expect(running, 2);
    expect(await gate.run(urgent: true, () async => 'screen'), 'screen');
    release.complete();
    await Future.wait(background);
  });

  test('the newest urgent request goes first, and one nobody wants is dropped', () async {
    final gate = RequestGate(1);
    final release = Completer<void>();
    final order = <String>[];
    var leftFirstCountry = false;
    final busy = gate.run(urgent: true, () async {
      order.add('busy');
      await release.future;
    });
    final first = gate.run(urgent: true, wanted: () => !leftFirstCountry, () async => order.add('first'));
    final second = gate.run(urgent: true, () async => order.add('second'));
    final dropped = expectLater(first, throwsA(isA<Unwanted>()));
    leftFirstCountry = true;
    release.complete();
    await busy;
    await second;
    await dropped;
    expect(order, ['busy', 'second']);
  });
}
