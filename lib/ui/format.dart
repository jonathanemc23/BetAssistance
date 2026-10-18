import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';

class Fmt {
  Fmt(this.settings) : _money = NumberFormat.simpleCurrency(name: settings.currency);
  final Settings settings;
  final NumberFormat _money;

  String money(double n, {bool sign = false}) {
    final s = _money.format(n.abs());
    if (n < -0.004) return '−$s';
    return (sign && n > 0.004 ? '+' : '') + s;
  }

  String pct(double n) =>
      '${n > 0.0004
          ? '+'
          : n < -0.0004
          ? '−'
          : ''}${(n.abs() * 100).toStringAsFixed(1)}%';

  String compact(double n) => NumberFormat.compact().format(n);

  static String date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : DateFormat.yMMMd().format(d);
  }
}

class BankColors {
  static const accent = Color(0xFF1D6B45);
  static Color win(BuildContext c) => _dark(c) ? const Color(0xFF55C98C) : const Color(0xFF1D7A4A);
  static Color loss(BuildContext c) => _dark(c) ? const Color(0xFFEF7562) : const Color(0xFFC2402F);
  static Color pending(BuildContext c) => _dark(c) ? const Color(0xFFE0A94A) : const Color(0xFFB7791F);
  static Color neutral(BuildContext c) => _dark(c) ? const Color(0xFF93A2AD) : const Color(0xFF6B7A86);
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color forValue(BuildContext c, double v) => v > 0.004
      ? win(c)
      : v < -0.004
      ? loss(c)
      : Theme.of(c).colorScheme.onSurface;

  static Color forStatus(BuildContext c, BetStatus s) => switch (s) {
    BetStatus.won => win(c),
    BetStatus.lost => loss(c),
    BetStatus.pending => pending(c),
    _ => neutral(c),
  };
}
