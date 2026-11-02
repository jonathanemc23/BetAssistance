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
        'dragon' => tr('The Dragon'),
        'oracle' => tr('The Oracle'),
        'wizard' => tr('The Wizard'),
        'shadow' => tr('The Shadow'),
        'mastermind' => tr('The Mastermind'),
        'king' => tr('The King'),
        'queen' => tr('The Queen'),
        'knight' => tr('The Dark Knight'),
        'raven' => tr('The Raven'),
        'wolf' => tr('The Wolf'),
        'phoenix' => tr('The Phoenix'),
        'serpent' => tr('The Serpent'),
        'masquerade' => tr('The Masquerade'),
        'reaper' => tr('The Reaper'),
        'crown' => tr('The Crown'),
        'fortune' => tr('Lady Luck'),
        'diamond' => tr('The Diamond'),
        'stallion' => tr('The Stallion'),
        'widow' => tr('The Black Widow'),
        'night' => tr('The Night'),
        _ => id,
      };
}

const legends = <Legend>[
  Legend('dragon', FontAwesomeIcons.dragon, Color(0xFF7A1A12), Color(0xFF150403), Color(0xFFFF6A3D), Metal.gold),
  Legend('oracle', FontAwesomeIcons.eye, Color(0xFF3E1C6E), Color(0xFF0C0618), Color(0xFFB27CFF), Metal.gold),
  Legend('wizard', FontAwesomeIcons.hatWizard, Color(0xFF1F2A78), Color(0xFF060918), Color(0xFF7FA6FF), Metal.silver),
  Legend('shadow', FontAwesomeIcons.userNinja, Color(0xFF1E3236), Color(0xFF050A0B), Color(0xFF3FD6C6), Metal.silver),
  Legend('mastermind', FontAwesomeIcons.userSecret, Color(0xFF2E2A24), Color(0xFF0A0907), Color(0xFFFFB547), Metal.gold),
  Legend('king', FontAwesomeIcons.chessKing, Color(0xFF14316B), Color(0xFF040A19), Color(0xFFFFD36B), Metal.gold),
  Legend('queen', FontAwesomeIcons.chessQueen, Color(0xFF5E1030), Color(0xFF14030A), Color(0xFFFF7FB0), Metal.gold),
  Legend('knight', FontAwesomeIcons.chessKnight, Color(0xFF2C3440), Color(0xFF07090C), Color(0xFF9FB6D6), Metal.silver),
  Legend('raven', FontAwesomeIcons.crow, Color(0xFF1A2236), Color(0xFF04060B), Color(0xFFC9D6FF), Metal.silver),
  Legend('wolf', FontAwesomeIcons.wolfPackBattalion, Color(0xFF233046), Color(0xFF05080E), Color(0xFF8FC3FF), Metal.silver),
  Legend('phoenix', FontAwesomeIcons.fireFlameCurved, Color(0xFF7A2A08), Color(0xFF170601), Color(0xFFFFA23D), Metal.gold),
  Legend('serpent', FontAwesomeIcons.staffSnake, Color(0xFF0F4A2E), Color(0xFF020F09), Color(0xFF4CF0A0), Metal.emerald),
  Legend('masquerade', FontAwesomeIcons.masksTheater, Color(0xFF4A1450), Color(0xFF100312), Color(0xFFE77CFF), Metal.gold),
  Legend('reaper', FontAwesomeIcons.skull, Color(0xFF2A0D0D), Color(0xFF060202), Color(0xFFFF3B3B), Metal.silver),
  Legend('crown', FontAwesomeIcons.crown, Color(0xFF40206A), Color(0xFF0D0618), Color(0xFFFFD36B), Metal.gold),
  Legend('fortune', FontAwesomeIcons.diceD20, Color(0xFF0E4A55), Color(0xFF021014), Color(0xFF5FE6F2), Metal.gold),
  Legend('diamond', FontAwesomeIcons.gem, Color(0xFF123E70), Color(0xFF030B17), Color(0xFF8FE3FF), Metal.silver),
  Legend('stallion', FontAwesomeIcons.horseHead, Color(0xFF4A2A14), Color(0xFF110803), Color(0xFFFFB27A), Metal.bronze),
  Legend('widow', FontAwesomeIcons.spider, Color(0xFF1A1A1F), Color(0xFF040405), Color(0xFFFF2E4D), Metal.crimson),
  Legend('night', FontAwesomeIcons.moon, Color(0xFF16204A), Color(0xFF03050F), Color(0xFFB9C8FF), Metal.silver),
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

    // Deep background, lit from just above the middle.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.85,
          colors: [Color.lerp(legend.inner, Colors.white, 0.08)!, legend.inner, legend.outer],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );

    // Nebula wisps in the legend's colour.
    void wisp(double x, double y, double r, double a) {
      final o = Offset(x * s, y * s);
      canvas.drawCircle(
        o,
        r * s,
        Paint()
          ..shader = RadialGradient(colors: [legend.glow.withValues(alpha: a), legend.glow.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: o, radius: r * s)),
      );
    }

    wisp(0.22, 0.25, 0.35, 0.22);
    wisp(0.82, 0.78, 0.4, 0.18);

    // Stars, placed the same way every time for a legend.
    final rnd = math.Random(legend.id.codeUnits.fold<int>(7, (h, u) => h * 31 + u) & 0x7fffffff);
    for (var i = 0; i < 22; i++) {
      final o = Offset(rnd.nextDouble() * s, rnd.nextDouble() * s);
      final r = (0.003 + rnd.nextDouble() * 0.009) * s;
      canvas.drawCircle(o, r, Paint()..color = Colors.white.withValues(alpha: 0.25 + rnd.nextDouble() * 0.55));
    }

    // Halo behind the emblem.
    canvas.drawCircle(
      c,
      0.36 * s,
      Paint()
        ..shader = RadialGradient(colors: [legend.glow.withValues(alpha: 0.55), legend.glow.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: 0.36 * s)),
    );

    // The emblem: a soft shadow, then the glyph in metal.
    TextPainter glyph(Paint paint) => TextPainter(
          text: TextSpan(
            text: String.fromCharCode(legend.icon.codePoint),
            style: TextStyle(
              fontFamily: legend.icon.fontFamily,
              package: legend.icon.fontPackage,
              fontSize: 0.46 * s,
              height: 1,
              foreground: paint,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    final shadow = glyph(Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.02 * s));
    final at = c - Offset(shadow.width / 2, shadow.height / 2);
    shadow.paint(canvas, at + Offset(0, 0.025 * s));
    final glyphRect = at & Size(shadow.width, shadow.height);
    glyph(Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: metal,
            stops: const [0, 0.5, 1],
          ).createShader(glyphRect))
        .paint(canvas, at);

    // Glassy shine across the top.
    canvas.drawOval(
      Rect.fromLTWH(0.12 * s, 0.02 * s, 0.76 * s, 0.42 * s),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, s, 0.44 * s)),
    );
    canvas.restore();

    // Metal rim with a fine inner line.
    final ring = Rect.fromCircle(center: c, radius: s / 2 - 0.022 * s);
    canvas.drawCircle(
      c,
      ring.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.044 * s
        ..shader = SweepGradient(
          colors: [metal[0], metal[1], metal[2], metal[1], metal[0], metal[1], metal[2], metal[1], metal[0]],
          transform: const GradientRotation(-math.pi / 3),
        ).createShader(ring),
    );
    canvas.drawCircle(
      c,
      s / 2 - 0.055 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.008 * s
        ..color = metal[0].withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_LegendPainter old) => old.legend != legend;
}
