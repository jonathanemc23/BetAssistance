import 'dart:async';
import 'dart:collection';

/// Lets only a few requests to one site run at a time, the urgent ones (what
/// the user is looking at) first. Firing a hundred requests at once made
/// phones time out and the feeds throttle the app.
class RequestGate {
  RequestGate(this.concurrent, {this.perMinute});

  final int concurrent;

  /// At most this many starts in any 60 seconds (TheSportsDB's free key
  /// answers 429 past about 30 a minute). Null for no limit.
  final int? perMinute;

  int _running = 0;
  final _urgent = Queue<Completer<void>>();
  final _normal = Queue<Completer<void>>();
  final _starts = Queue<DateTime>();
  Timer? _wake;

  /// Runs [task] when its turn comes. With a per-minute limit, a background
  /// task that would have to wait for the next minute throws [GateFull]
  /// instead, keeping the last few starts for urgent ones.
  Future<T> run<T>(Future<T> Function() task, {bool urgent = false}) async {
    final cap = perMinute;
    if (!urgent && cap != null && _recent + _urgent.length + _normal.length >= cap - _keepForUrgent) {
      throw const GateFull();
    }
    if (_urgent.isEmpty && (urgent || _normal.isEmpty) && _free) {
      _take();
    } else {
      final turn = Completer<void>();
      (urgent ? _urgent : _normal).add(turn);
      _next();
      await turn.future;
    }
    try {
      return await task();
    } finally {
      _running--;
      _next();
    }
  }

  static const _keepForUrgent = 5;

  /// Starts in the last 60 seconds.
  int get _recent {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    while (_starts.isNotEmpty && _starts.first.isBefore(cutoff)) {
      _starts.removeFirst();
    }
    return _starts.length;
  }

  bool get _free {
    if (_running >= concurrent) return false;
    final cap = perMinute;
    return cap == null || _recent < cap;
  }

  void _take() {
    _running++;
    if (perMinute != null) _starts.add(DateTime.now());
  }

  void _next() {
    while ((_urgent.isNotEmpty || _normal.isNotEmpty) && _free) {
      _take();
      (_urgent.isNotEmpty ? _urgent : _normal).removeFirst().complete();
    }
    // Waiting on the per-minute limit: look again when the oldest start
    // leaves the window.
    if ((_urgent.isNotEmpty || _normal.isNotEmpty) && _running < concurrent && _starts.isNotEmpty && _wake == null) {
      final wait = _starts.first.add(const Duration(minutes: 1)).difference(DateTime.now());
      _wake = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 50), () {
        _wake = null;
        _next();
      });
    }
  }
}

/// A background request skipped to stay within a feed's per-minute limit.
class GateFull implements Exception {
  const GateFull();
}
