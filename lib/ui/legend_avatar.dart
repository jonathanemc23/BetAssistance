import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/l10n.dart';

/// The finish of a legend's emblem and ring.
enum Metal {
  gold([Color(0xFFFFF3C9), Color(0xFFE4B85C), Color(0xFF9A6A1C)]),
  silver([Color(0xFFFFFFFF), Color(0xFFCBD3DC), Color(0xFF6F7A88)]),
  bronze([Color(0xFFFFE0C2), Color(0xFFC98A4E), Color(0xFF6E3F18)]),
  crimson([Color(0xFFFFD2C9), Color(0xFFE0533C), Color(0xFF7A1408)]),
  emerald([Color(0xFFDDFBE8), Color(0xFF4CC984), Color(0xFF14593A)]);

  const Metal(this.shades);

  /// Light, middle and dark.
  final List<Color> shades;
}

/// A legend avatar: a metal emblem on a dark, starry medallion. Saved as
/// `legend:<id>`; the id never changes.
class Legend {
  const Legend(this.id, this.icon, this.inner, this.outer, this.glow, this.metal);
  final String id;
  final FaIconData icon;
  final Color inner, outer, glow;
  final Metal metal;

  /// The legend's title in the app's language.
  String get name => switch (id) {
        'dragon' => tr('The Rook'),
        'oracle' => tr('The Navigator'),
        'wizard' => tr('The Bishop'),
        'shadow' => tr('The Guardian'),
        'mastermind' => tr('The Strategist'),
        'king' => tr('The King'),
        'queen' => tr('The Queen'),
        'knight' => tr('The Knight'),
        'raven' => tr('The Scribe'),
        'wolf' => tr('The Summit'),
        'phoenix' => tr('The Marksman'),
        'serpent' => tr('The Analyst'),
        'masquerade' => tr('The Key'),
        'reaper' => tr('The Anchor'),
        'crown' => tr('The Crown'),
        'fortune' => tr('The Champion'),
        'diamond' => tr('The Diamond'),
        'stallion' => tr('The Stallion'),
        'widow' => tr('The Vault'),
        'night' => tr('The Night'),
        _ => id,
      };
}

// Muted grounds: navy, oxblood, forest, graphite, slate and plum.
const _navy = (Color(0xFF1B2638), Color(0xFF0B1018));
const _oxblood = (Color(0xFF3A1A1C), Color(0xFF140809));
const _forest = (Color(0xFF1C2E26), Color(0xFF0A120E));
const _graphite = (Color(0xFF26272B), Color(0xFF0C0C0E));
const _slate = (Color(0xFF243039), Color(0xFF0C1115));
const _plum = (Color(0xFF2C2131), Color(0xFF0F0A11));

Legend _l(String id, FaIconData icon, (Color, Color) ground, Metal metal) =>
    Legend(id, icon, ground.$1, ground.$2, metal.shades[1], metal);

/// The ids are saved in profiles and never change; their emblems and names
/// may.
final legends = <Legend>[
  _l('king', FontAwesomeIcons.chessKing, _navy, Metal.gold),
  _l('queen', FontAwesomeIcons.chessQueen, _oxblood, Metal.gold),
  _l('knight', FontAwesomeIcons.chessKnight, _graphite, Metal.silver),
  _l('dragon', FontAwesomeIcons.chessRook, _forest, Metal.gold),
  _l('wizard', FontAwesomeIcons.chessBishop, _slate, Metal.silver),
  _l('crown', FontAwesomeIcons.crown, _plum, Metal.gold),
  _l('diamond', FontAwesomeIcons.gem, _navy, Metal.silver),
  _l('fortune', FontAwesomeIcons.trophy, _graphite, Metal.gold),
  _l('mastermind', FontAwesomeIcons.scaleBalanced, _oxblood, Metal.silver),
  _l('serpent', FontAwesomeIcons.chartLine, _forest, Metal.silver),
  _l('phoenix', FontAwesomeIcons.bullseye, _slate, Metal.gold),
  _l('oracle', FontAwesomeIcons.compass, _navy, Metal.bronze),
  _l('shadow', FontAwesomeIcons.shieldHalved, _graphite, Metal.bronze),
  _l('widow', FontAwesomeIcons.landmark, _forest, Metal.bronze),
  _l('masquerade', FontAwesomeIcons.key, _plum, Metal.silver),
  _l('reaper', FontAwesomeIcons.anchor, _slate, Metal.bronze),
  _l('raven', FontAwesomeIcons.featherPointed, _oxblood, Metal.bronze),
  _l('wolf', FontAwesomeIcons.mountain, _slate, Metal.silver),
  _l('stallion', FontAwesomeIcons.horseHead, _graphite, Metal.bronze),
  _l('night', FontAwesomeIcons.moon, _navy, Metal.silver),
];

/// The legend in an avatar value (`legend:<id>`), if it is one.
Legend? legendOf(String avatar) {
  if (!avatar.startsWith('legend:')) return null;
  final id = avatar.substring(7);
  for (final l in legends) {
    if (l.id == id) return l;
  }
  return null;
}

/// Draws a [Legend] as a round medallion.
class LegendAvatar extends StatelessWidget {
  const LegendAvatar({super.key, required this.legend, this.size = 56});
  final Legend legend;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: legend.name,
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _LegendPainter(legend))),
      );
}

/// A signet: a matte, dark ground, the emblem in brushed metal and a thin
/// metal rim. No stars, glows or bright colours.
class _LegendPainter extends CustomPainter {
  _LegendPainter(this.legend);
  final Legend legend;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final rect = Offset.zero & size;
    final metal = legend.metal.shades;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // Matte ground, a touch lighter at the top.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [legend.inner, legend.outer],
        ).createShader(rect),
    );

    // The emblem in brushed metal, with a faint shadow.
    TextPainter glyph(Paint paint) => TextPainter(
          text: TextSpan(
            text: String.fromCharCode(legend.icon.codePoint),
            style: TextStyle(
              fontFamily: legend.icon.fontFamily,
              package: legend.icon.fontPackage,
              fontSize: 0.4 * s,
              height: 1,
              foreground: paint,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    final shadow = glyph(Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.012 * s));
    final at = c - Offset(shadow.width / 2, shadow.height / 2);
    shadow.paint(canvas, at + Offset(0, 0.015 * s));
    final glyphRect = at & Size(shadow.width, shadow.height);
    glyph(Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [metal[0], metal[1], Color.lerp(metal[1], metal[2], 0.5)!],
          ).createShader(glyphRect))
        .paint(canvas, at);
    canvas.restore();

    // Thin metal rim and a fine inner line.
    final ring = Rect.fromCircle(center: c, radius: s / 2 - 0.016 * s);
    canvas.drawCircle(
      c,
      ring.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.032 * s
        ..shader = SweepGradient(
          colors: [metal[1], metal[0], metal[1], metal[2], metal[1]],
          transform: const GradientRotation(-math.pi / 4),
        ).createShader(ring),
    );
    canvas.drawCircle(
      c,
      s / 2 - 0.075 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.006 * s
        ..color = metal[1].withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_LegendPainter old) => old.legend != legend;
}
