import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a preset person avatar looks: skin, hair, clothes and extras.
enum HairStyle { short, buzz, curly, long, bun, ponytail, bald, quiff, bob }

/// Something on the head, drawn over the hair.
enum Headwear { none, cap, beanie, headband }

class PersonLook {
  const PersonLook({
    required this.skin,
    required this.hair,
    required this.hairColor,
    required this.shirt,
    required this.background,
    this.beard = false,
    this.glasses = false,
    this.earrings = false,
    this.eyes = const Color(0xFF5B3A23),
    this.grin = false,
    this.headwear = Headwear.none,
    this.headwearColor = const Color(0xFF1F2A44),
    this.accent = Colors.white,
    this.number,
    this.scarf = false,
    this.headphones = false,
    this.sunglasses = false,
  });
  final Color skin;
  final HairStyle hair;
  final Color hairColor;
  final Color shirt;
  final Color background;
  final bool beard;
  final bool glasses;
  final bool earrings;

  /// Iris colour.
  final Color eyes;

  /// A wide smile with teeth instead of a closed one.
  final bool grin;
  final Headwear headwear;
  final Color headwearColor;

  /// Trim of a jersey, the stripes of a scarf and the details of a hat.
  final Color accent;

  /// A jersey with this number; null for a plain T-shirt.
  final int? number;
  final bool scarf;
  final bool headphones;
  final bool sunglasses;
}

const _black = Color(0xFF241A14), _brown = Color(0xFF5A3825), _blond = Color(0xFFD8A64A), _red = Color(0xFFA4452A);
const _grey = Color(0xFFB9B4AE), _chestnut = Color(0xFF7A4A2A);
const _blueEyes = Color(0xFF4A7BB0), _greenEyes = Color(0xFF5E8A4E), _hazel = Color(0xFF8A6A35);

/// The preset people, saved as `person:<index>`. Append new looks at the end:
/// the index is what users have saved.
const personLooks = <PersonLook>[
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.short, hairColor: _brown, shirt: Color(0xFF2E9461), background: Color(0xFFCFE8D9), number: 10, accent: Color(0xFFF2F2F2), grin: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.long, hairColor: _blond, shirt: Color(0xFF8E5BD0), background: Color(0xFFE6DAF6), earrings: true, eyes: _blueEyes),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.curly, hairColor: _black, shirt: Color(0xFFE0A93B), background: Color(0xFFF6E3BC), grin: true),
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.bun, hairColor: _black, shirt: Color(0xFFC2402F), background: Color(0xFFF5D4CE), earrings: true),
  PersonLook(skin: Color(0xFF9E6640), hair: HairStyle.buzz, hairColor: _black, shirt: Color(0xFF3D7DD8), background: Color(0xFFD3E2F7), beard: true, number: 23, accent: Color(0xFFF2C94C)),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.quiff, hairColor: _red, shirt: Color(0xFF2A9BA5), background: Color(0xFFCFEDEF), glasses: true, eyes: _greenEyes, grin: true),
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.ponytail, hairColor: _brown, shirt: Color(0xFF2E9461), background: Color(0xFFE2EFD0), eyes: _hazel),
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.bald, hairColor: _black, shirt: Color(0xFF35424F), background: Color(0xFFD9DEE3), beard: true, grin: true),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.bob, hairColor: _black, shirt: Color(0xFFD9467A), background: Color(0xFFF7D6E2), glasses: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.short, hairColor: _grey, shirt: Color(0xFF6B4D16), background: Color(0xFFEDE3CF), glasses: true, beard: true, eyes: _blueEyes),
  PersonLook(skin: Color(0xFF9E6640), hair: HairStyle.long, hairColor: _black, shirt: Color(0xFF3D7DD8), background: Color(0xFFDCE4F9), grin: true),
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.curly, hairColor: _blond, shirt: Color(0xFFC2402F), background: Color(0xFFF8DCCB), eyes: _greenEyes),
  // Fans: caps, beanies, scarves and jerseys.
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.short, hairColor: _black, shirt: Color(0xFF1F2A44), background: Color(0xFFD6DCEB), headwear: Headwear.cap, headwearColor: Color(0xFFC2402F), accent: Color(0xFFF2F2F2), number: 7, grin: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.long, hairColor: _chestnut, shirt: Color(0xFF2E9461), background: Color(0xFFD5EBDD), headwear: Headwear.beanie, headwearColor: Color(0xFF2E9461), accent: Color(0xFFF2F2F2), scarf: true, eyes: _hazel, grin: true),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.buzz, hairColor: _black, shirt: Color(0xFFE0A93B), background: Color(0xFFF7E7C4), headphones: true, accent: Color(0xFF1F2A44), number: 30),
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.quiff, hairColor: _blond, shirt: Color(0xFF35424F), background: Color(0xFFDDE3E8), sunglasses: true, beard: true, grin: true),
  PersonLook(skin: Color(0xFF9E6640), hair: HairStyle.curly, hairColor: _black, shirt: Color(0xFFC2402F), background: Color(0xFFF6D7D0), headwear: Headwear.headband, headwearColor: Color(0xFFF2F2F2), accent: Color(0xFFC2402F), number: 8, earrings: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.ponytail, hairColor: _red, shirt: Color(0xFF3D7DD8), background: Color(0xFFD6E4F8), headwear: Headwear.cap, headwearColor: Color(0xFF3D7DD8), accent: Color(0xFFF2C94C), eyes: _greenEyes, grin: true),
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.bald, hairColor: _black, shirt: Color(0xFF8E5BD0), background: Color(0xFFE7DCF6), headwear: Headwear.beanie, headwearColor: Color(0xFF35424F), accent: Color(0xFFF2C94C), scarf: true, beard: true),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.bun, hairColor: _black, shirt: Color(0xFF2A9BA5), background: Color(0xFFD0ECEE), headphones: true, accent: Color(0xFFD9467A), glasses: true, grin: true),
];

/// Draws a [PersonLook] as a round, flat illustration with soft shading:
/// background, shoulders, head, hair, face and extras.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.look, this.size = 56});
  final PersonLook look;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PersonPainter(look)),
      );
}

class _PersonPainter extends CustomPainter {
  _PersonPainter(this.look);
  final PersonLook look;

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Rect r(double l, double t, double w, double h) => Rect.fromLTWH(l * s, t * s, w * s, h * s);
    Paint fill(Color c) => Paint()
      ..isAntiAlias = true
      ..color = c;
    Paint shaded(Rect rect, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter}) =>
        Paint()
          ..isAntiAlias = true
          ..shader = LinearGradient(begin: begin, end: end, colors: colors).createShader(rect);
    Paint stroke(Color c, double w) => Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w * s
      ..color = c;

    final skin = look.skin;
    final skinLight = _mix(skin, Colors.white, 0.16), skinShade = _mix(skin, Colors.black, 0.16);
    final hair = look.hairColor, hairDark = _mix(hair, Colors.black, 0.3), hairLight = _mix(hair, Colors.white, 0.22);
    final shirtLight = _mix(look.shirt, Colors.white, 0.14), shirtDark = _mix(look.shirt, Colors.black, 0.22);

    canvas.save();
    canvas.clipPath(Path()..addOval(r(0, 0, 1, 1)));

    // Background: soft light from the top and two faint stadium beams.
    canvas.drawRect(
      r(0, 0, 1, 1),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.6),
          radius: 1.0,
          colors: [_mix(look.background, Colors.white, 0.45), look.background, _mix(look.background, Colors.black, 0.08)],
          stops: const [0, 0.6, 1],
        ).createShader(r(0, 0, 1, 1)),
    );
    final beam = fill(Colors.white.withValues(alpha: 0.16));
    canvas.drawPath(Path()..moveTo(0.05 * s, 0)..lineTo(0.22 * s, 0)..lineTo(0.48 * s, s)..lineTo(0.3 * s, s)..close(), beam);
    canvas.drawPath(Path()..moveTo(0.78 * s, 0)..lineTo(0.88 * s, 0)..lineTo(0.7 * s, s)..lineTo(0.6 * s, s)..close(), beam);

    // The person fills more of the circle than the unit drawing below.
    canvas.translate(0.5 * s, 0.6 * s);
    canvas.scale(1.2);
    canvas.translate(-0.5 * s, -0.6 * s);

    // Hair that falls behind the head and shoulders.
    final backHair = shaded(r(0.24, 0.18, 0.52, 0.64), [hair, hairDark]);
    switch (look.hair) {
      case HairStyle.long:
        canvas.drawRRect(RRect.fromRectAndRadius(r(0.26, 0.2, 0.48, 0.6), Radius.circular(0.2 * s)), backHair);
      case HairStyle.bob:
        canvas.drawRRect(RRect.fromRectAndRadius(r(0.25, 0.2, 0.5, 0.42), Radius.circular(0.16 * s)), backHair);
      case HairStyle.ponytail:
        canvas.drawPath(
          Path()
            ..moveTo(0.64 * s, 0.3 * s)
            ..quadraticBezierTo(0.86 * s, 0.38 * s, 0.76 * s, 0.66 * s)
            ..quadraticBezierTo(0.72 * s, 0.5 * s, 0.62 * s, 0.4 * s)
            ..close(),
          backHair,
        );
      case HairStyle.curly:
        for (final (x, y, rad) in [(0.29, 0.38, 0.085), (0.71, 0.38, 0.085), (0.27, 0.5, 0.07), (0.73, 0.5, 0.07)]) {
          canvas.drawCircle(p(x, y), rad * s, backHair);
        }
      default:
        break;
    }

    // Shoulders: a T-shirt or a jersey, lit from above.
    final body = Path()
      ..moveTo(0.1 * s, 1.1 * s)
      ..quadraticBezierTo(0.1 * s, 0.8 * s, 0.38 * s, 0.75 * s)
      ..lineTo(0.62 * s, 0.75 * s)
      ..quadraticBezierTo(0.9 * s, 0.8 * s, 0.9 * s, 1.1 * s)
      ..close();
    canvas.drawPath(body, shaded(r(0.1, 0.74, 0.8, 0.36), [shirtLight, look.shirt, shirtDark]));
    // Folds by the arms.
    canvas.drawPath(
        Path()
          ..moveTo(0.24 * s, 0.84 * s)
          ..quadraticBezierTo(0.26 * s, 0.95 * s, 0.24 * s, 1.05 * s),
        stroke(shirtDark.withValues(alpha: 0.5), 0.012));
    canvas.drawPath(
        Path()
          ..moveTo(0.76 * s, 0.84 * s)
          ..quadraticBezierTo(0.74 * s, 0.95 * s, 0.76 * s, 1.05 * s),
        stroke(shirtDark.withValues(alpha: 0.5), 0.012));

    // Neck, with the shadow under the chin.
    canvas.drawRRect(RRect.fromRectAndRadius(r(0.42, 0.56, 0.16, 0.24), Radius.circular(0.06 * s)), fill(skin));
    canvas.drawPath(
      Path()
        ..moveTo(0.42 * s, 0.6 * s)
        ..quadraticBezierTo(0.5 * s, 0.7 * s, 0.58 * s, 0.6 * s)
        ..lineTo(0.58 * s, 0.66 * s)
        ..quadraticBezierTo(0.5 * s, 0.74 * s, 0.42 * s, 0.66 * s)
        ..close(),
      fill(skinShade),
    );

    // Collar: a jersey's V-neck with trim, or a round T-shirt neck.
    if (look.number != null) {
      canvas.drawPath(
        Path()
          ..moveTo(0.38 * s, 0.75 * s)
          ..lineTo(0.5 * s, 0.87 * s)
          ..lineTo(0.62 * s, 0.75 * s),
        stroke(look.accent, 0.03),
      );
      canvas.drawPath(
        Path()
          ..moveTo(0.4 * s, 0.75 * s)
          ..lineTo(0.5 * s, 0.85 * s)
          ..lineTo(0.6 * s, 0.75 * s)
          ..close(),
        fill(skin),
      );
      // Shoulder stripes and the number on the chest.
      canvas.drawLine(p(0.2, 0.86), p(0.3, 0.79), stroke(look.accent, 0.018));
      canvas.drawLine(p(0.8, 0.86), p(0.7, 0.79), stroke(look.accent, 0.018));
      final tp = TextPainter(
        text: TextSpan(
          text: '${look.number}',
          style: TextStyle(color: look.accent, fontSize: 0.11 * s, fontWeight: FontWeight.w900, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p(0.66, 0.88) - Offset(tp.width / 2, tp.height / 2));
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(0.39 * s, 0.75 * s)
          ..quadraticBezierTo(0.5 * s, 0.86 * s, 0.61 * s, 0.75 * s),
        stroke(shirtDark, 0.022),
      );
    }

    // Scarf round the neck, in stripes, with a hanging end.
    if (look.scarf) {
      final band = RRect.fromRectAndRadius(r(0.34, 0.7, 0.32, 0.1), Radius.circular(0.05 * s));
      canvas.drawRRect(band, fill(look.headwearColor));
      canvas.save();
      canvas.clipRRect(band);
      for (var x = 0.36; x < 0.66; x += 0.08) {
        canvas.drawRect(r(x, 0.7, 0.035, 0.1), fill(look.accent));
      }
      canvas.restore();
      final end = RRect.fromRectAndRadius(r(0.55, 0.76, 0.08, 0.22), Radius.circular(0.02 * s));
      canvas.drawRRect(end, fill(look.headwearColor));
      canvas.save();
      canvas.clipRRect(end);
      for (var y = 0.79; y < 0.98; y += 0.06) {
        canvas.drawRect(r(0.55, y, 0.08, 0.025), fill(look.accent));
      }
      canvas.restore();
    }

    // Ears.
    for (final x in [0.27, 0.65]) {
      canvas.drawOval(r(x, 0.42, 0.08, 0.11), fill(skin));
      canvas.drawOval(r(x + 0.02, 0.445, 0.04, 0.06), fill(skinShade));
    }
    if (look.earrings) {
      canvas.drawCircle(p(0.305, 0.55), 0.018 * s, fill(const Color(0xFFF2C94C)));
      canvas.drawCircle(p(0.695, 0.55), 0.018 * s, fill(const Color(0xFFF2C94C)));
      canvas.drawCircle(p(0.3, 0.545), 0.006 * s, fill(Colors.white.withValues(alpha: 0.8)));
      canvas.drawCircle(p(0.69, 0.545), 0.006 * s, fill(Colors.white.withValues(alpha: 0.8)));
    }

    // Head, lit from the top left.
    final head = r(0.31, 0.24, 0.38, 0.42);
    canvas.drawOval(
      head,
      Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.45),
          radius: 0.95,
          colors: [skinLight, skin, skinShade],
          stops: const [0, 0.6, 1],
        ).createShader(head),
    );

    // Beard along the jaw, with a moustache.
    if (look.beard) {
      final beard = shaded(r(0.31, 0.45, 0.38, 0.22), [hair, hairDark]);
      canvas.drawPath(
        Path()
          ..moveTo(0.31 * s, 0.45 * s)
          ..quadraticBezierTo(0.31 * s, 0.67 * s, 0.5 * s, 0.67 * s)
          ..quadraticBezierTo(0.69 * s, 0.67 * s, 0.69 * s, 0.45 * s)
          ..lineTo(0.66 * s, 0.47 * s)
          ..quadraticBezierTo(0.64 * s, 0.56 * s, 0.56 * s, 0.555 * s)
          ..quadraticBezierTo(0.5 * s, 0.535 * s, 0.44 * s, 0.555 * s)
          ..quadraticBezierTo(0.36 * s, 0.56 * s, 0.34 * s, 0.47 * s)
          ..close(),
        beard,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0.43 * s, 0.545 * s)
          ..quadraticBezierTo(0.5 * s, 0.51 * s, 0.57 * s, 0.545 * s)
          ..quadraticBezierTo(0.5 * s, 0.535 * s, 0.43 * s, 0.545 * s)
          ..close(),
        stroke(hairDark, 0.018),
      );
    }

    // Hair on top of the head, with a shine.
    final topHair = shaded(r(0.27, 0.17, 0.46, 0.33), [hairLight, hair, hairDark]);
    final cap = Path()
      ..moveTo(0.3 * s, 0.44 * s)
      ..cubicTo(0.27 * s, 0.2 * s, 0.73 * s, 0.2 * s, 0.7 * s, 0.44 * s)
      ..quadraticBezierTo(0.66 * s, 0.33 * s, 0.56 * s, 0.32 * s)
      ..quadraticBezierTo(0.42 * s, 0.31 * s, 0.36 * s, 0.36 * s)
      ..quadraticBezierTo(0.32 * s, 0.39 * s, 0.3 * s, 0.44 * s)
      ..close();
    final shine = stroke(Colors.white.withValues(alpha: 0.28), 0.016);
    switch (look.hair) {
      case HairStyle.short:
        canvas.drawPath(cap, topHair);
        canvas.drawArc(r(0.38, 0.23, 0.18, 0.12), math.pi * 1.1, math.pi * 0.5, false, shine);
      case HairStyle.buzz:
        canvas.drawPath(
          Path()
            ..moveTo(0.31 * s, 0.4 * s)
            ..cubicTo(0.31 * s, 0.2 * s, 0.69 * s, 0.2 * s, 0.69 * s, 0.4 * s)
            ..quadraticBezierTo(0.5 * s, 0.3 * s, 0.31 * s, 0.4 * s)
            ..close(),
          topHair..color = hair.withValues(alpha: 0.9),
        );
      case HairStyle.curly:
        for (final (x, y, rad) in [
          (0.34, 0.31, 0.08), (0.43, 0.25, 0.085), (0.53, 0.24, 0.085), (0.62, 0.28, 0.08), (0.68, 0.36, 0.065),
          (0.32, 0.38, 0.06), (0.5, 0.3, 0.07),
        ]) {
          canvas.drawCircle(p(x, y), rad * s, topHair);
          canvas.drawArc(Rect.fromCircle(center: p(x, y), radius: rad * s * 0.6), math.pi * 1.1, math.pi * 0.5, false,
              stroke(Colors.white.withValues(alpha: 0.2), 0.01));
        }
      case HairStyle.long || HairStyle.bob:
        canvas.drawPath(
          Path()
            ..moveTo(0.3 * s, 0.5 * s)
            ..cubicTo(0.26 * s, 0.18 * s, 0.74 * s, 0.18 * s, 0.7 * s, 0.5 * s)
            ..quadraticBezierTo(0.66 * s, 0.34 * s, 0.5 * s, 0.31 * s)
            ..quadraticBezierTo(0.36 * s, 0.33 * s, 0.3 * s, 0.5 * s)
            ..close(),
          topHair,
        );
        canvas.drawArc(r(0.36, 0.22, 0.2, 0.14), math.pi * 1.1, math.pi * 0.5, false, shine);
      case HairStyle.bun:
        canvas.drawCircle(p(0.5, 0.2), 0.08 * s, topHair);
        canvas.drawPath(cap, topHair);
        canvas.drawArc(r(0.46, 0.15, 0.06, 0.05), math.pi * 1.1, math.pi * 0.6, false, shine);
      case HairStyle.ponytail:
        canvas.drawPath(cap, topHair);
        canvas.drawCircle(p(0.68, 0.33), 0.025 * s, fill(look.accent == Colors.white ? hairDark : look.accent));
        canvas.drawArc(r(0.38, 0.23, 0.18, 0.12), math.pi * 1.1, math.pi * 0.5, false, shine);
      case HairStyle.quiff:
        canvas.drawPath(cap, topHair);
        canvas.drawPath(
          Path()
            ..moveTo(0.38 * s, 0.3 * s)
            ..quadraticBezierTo(0.46 * s, 0.13 * s, 0.66 * s, 0.22 * s)
            ..quadraticBezierTo(0.56 * s, 0.24 * s, 0.6 * s, 0.31 * s)
            ..close(),
          topHair,
        );
        canvas.drawPath(
            Path()
              ..moveTo(0.44 * s, 0.25 * s)
              ..quadraticBezierTo(0.5 * s, 0.18 * s, 0.6 * s, 0.21 * s),
            shine);
      case HairStyle.bald:
        canvas.drawOval(r(0.3, 0.38, 0.05, 0.08), fill(hair.withValues(alpha: 0.75)));
        canvas.drawOval(r(0.65, 0.38, 0.05, 0.08), fill(hair.withValues(alpha: 0.75)));
        canvas.drawOval(r(0.41, 0.27, 0.13, 0.05), fill(Colors.white.withValues(alpha: 0.25)));
    }

    _headwear(canvas, s, p, r, fill, shaded, stroke);

    // Face: brows, eyes, nose, cheeks and mouth.
    final browY = look.headwear == Headwear.cap ? 0.42 : 0.41;
    final brow = stroke(hairDark, 0.022);
    canvas.drawPath(
        Path()
          ..moveTo(0.38 * s, (browY + 0.012) * s)
          ..quadraticBezierTo(0.42 * s, (browY - 0.014) * s, 0.465 * s, browY * s),
        brow);
    canvas.drawPath(
        Path()
          ..moveTo(0.535 * s, browY * s)
          ..quadraticBezierTo(0.58 * s, (browY - 0.014) * s, 0.62 * s, (browY + 0.012) * s),
        brow);

    if (!look.sunglasses) {
      for (final x in [0.425, 0.575]) {
        canvas.drawOval(Rect.fromCenter(center: p(x, 0.462), width: 0.062 * s, height: 0.046 * s), fill(Colors.white));
        canvas.drawCircle(p(x + 0.003, 0.463), 0.019 * s, fill(look.eyes));
        canvas.drawCircle(p(x + 0.003, 0.463), 0.0095 * s, fill(const Color(0xFF15100C)));
        canvas.drawCircle(p(x + 0.01, 0.456), 0.0055 * s, fill(Colors.white));
        canvas.drawArc(Rect.fromCenter(center: p(x, 0.462), width: 0.066 * s, height: 0.05 * s), math.pi * 1.05,
            math.pi * 0.9, false, stroke(const Color(0xFF2B211B), 0.01));
      }
    }

    // Nose: a soft shadow down one side and the tip.
    canvas.drawPath(
        Path()
          ..moveTo(0.505 * s, 0.47 * s)
          ..quadraticBezierTo(0.52 * s, 0.51 * s, 0.505 * s, 0.522 * s),
        stroke(skinShade, 0.014));
    canvas.drawCircle(p(0.495, 0.515), 0.008 * s, fill(skinLight.withValues(alpha: 0.7)));

    canvas.drawCircle(p(0.375, 0.53), 0.032 * s, fill(const Color(0xFFE5776B).withValues(alpha: 0.22)));
    canvas.drawCircle(p(0.625, 0.53), 0.032 * s, fill(const Color(0xFFE5776B).withValues(alpha: 0.22)));

    if (look.grin) {
      final mouth = Path()
        ..moveTo(0.44 * s, 0.548 * s)
        ..quadraticBezierTo(0.5 * s, 0.556 * s, 0.56 * s, 0.548 * s)
        ..quadraticBezierTo(0.555 * s, 0.61 * s, 0.5 * s, 0.61 * s)
        ..quadraticBezierTo(0.445 * s, 0.61 * s, 0.44 * s, 0.548 * s)
        ..close();
      canvas.drawPath(mouth, fill(const Color(0xFF7A2E28)));
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawRect(r(0.43, 0.54, 0.14, 0.025), fill(Colors.white));
      canvas.drawOval(r(0.465, 0.585, 0.07, 0.04), fill(const Color(0xFFD9625A)));
      canvas.restore();
    } else {
      canvas.drawArc(r(0.44, 0.5, 0.12, 0.075), 0.3, math.pi - 0.6, false, stroke(const Color(0xFF8C3B32), 0.02));
    }

    if (look.glasses) {
      final frame = stroke(const Color(0xFF2B2B2B), 0.016);
      for (final x in [0.372, 0.528]) {
        final lens = RRect.fromRectAndRadius(r(x, 0.425, 0.1, 0.075), Radius.circular(0.025 * s));
        canvas.drawRRect(lens, fill(Colors.white.withValues(alpha: 0.12)));
        canvas.drawRRect(lens, frame);
        canvas.drawLine(p(x + 0.02, 0.44), p(x + 0.04, 0.435), stroke(Colors.white.withValues(alpha: 0.5), 0.008));
      }
      canvas.drawLine(p(0.472, 0.455), p(0.528, 0.455), frame);
    }
    if (look.sunglasses) {
      final frame = stroke(const Color(0xFF151515), 0.016);
      for (final x in [0.365, 0.525]) {
        final lens = RRect.fromRectAndCorners(r(x, 0.43, 0.11, 0.07),
            topLeft: Radius.circular(0.015 * s),
            topRight: Radius.circular(0.015 * s),
            bottomLeft: Radius.circular(0.035 * s),
            bottomRight: Radius.circular(0.035 * s));
        canvas.drawRRect(
            lens,
            shaded(lens.outerRect, const [Color(0xFF3A3F4B), Color(0xFF101216)],
                begin: Alignment.topLeft, end: Alignment.bottomRight));
        canvas.drawRRect(lens, frame);
        canvas.drawLine(p(x + 0.02, 0.45), p(x + 0.05, 0.442), stroke(Colors.white.withValues(alpha: 0.45), 0.01));
      }
      canvas.drawLine(p(0.475, 0.448), p(0.525, 0.448), frame);
    }

    if (look.headphones) {
      final band = stroke(const Color(0xFF22252B), 0.035);
      canvas.drawArc(r(0.27, 0.15, 0.46, 0.5), math.pi * 1.02, math.pi * 0.96, false, band);
      for (final x in [0.245, 0.675]) {
        final cup = RRect.fromRectAndRadius(r(x, 0.39, 0.08, 0.15), Radius.circular(0.035 * s));
        canvas.drawRRect(cup, shaded(cup.outerRect, const [Color(0xFF3A3F48), Color(0xFF15171B)]));
        canvas.drawRRect(cup, stroke(look.accent, 0.012));
      }
    }
    canvas.restore();
  }

  void _headwear(
    Canvas canvas,
    double s,
    Offset Function(double, double) p,
    Rect Function(double, double, double, double) r,
    Paint Function(Color) fill,
    Paint Function(Rect, List<Color>, {Alignment begin, Alignment end}) shaded,
    Paint Function(Color, double) stroke,
  ) {
    final c = look.headwearColor;
    final light = _mix(c, Colors.white, 0.18), dark = _mix(c, Colors.black, 0.25);
    switch (look.headwear) {
      case Headwear.none:
        return;
      case Headwear.cap:
        // Crown, seams, button, front badge and the brim.
        final crown = Path()
          ..moveTo(0.285 * s, 0.4 * s)
          ..cubicTo(0.27 * s, 0.13 * s, 0.73 * s, 0.13 * s, 0.715 * s, 0.4 * s)
          ..quadraticBezierTo(0.5 * s, 0.36 * s, 0.285 * s, 0.4 * s)
          ..close();
        canvas.drawPath(crown, shaded(r(0.27, 0.16, 0.46, 0.25), [light, c, dark]));
        canvas.drawPath(
            Path()
              ..moveTo(0.5 * s, 0.18 * s)
              ..quadraticBezierTo(0.47 * s, 0.28 * s, 0.5 * s, 0.37 * s),
            stroke(dark, 0.008));
        canvas.drawCircle(p(0.5, 0.18), 0.018 * s, fill(dark));
        canvas.drawCircle(p(0.43, 0.3), 0.032 * s, fill(look.accent));
        canvas.drawPath(
          Path()
            ..moveTo(0.27 * s, 0.4 * s)
            ..quadraticBezierTo(0.5 * s, 0.34 * s, 0.73 * s, 0.4 * s)
            ..quadraticBezierTo(0.5 * s, 0.45 * s, 0.27 * s, 0.4 * s)
            ..close(),
          fill(dark),
        );
      case Headwear.beanie:
        final dome = Path()
          ..moveTo(0.29 * s, 0.38 * s)
          ..cubicTo(0.27 * s, 0.1 * s, 0.73 * s, 0.1 * s, 0.71 * s, 0.38 * s)
          ..close();
        canvas.drawPath(dome, shaded(r(0.27, 0.14, 0.46, 0.24), [light, c, dark]));
        canvas.drawCircle(p(0.5, 0.15), 0.045 * s, fill(look.accent));
        canvas.drawCircle(p(0.49, 0.14), 0.02 * s, fill(Colors.white.withValues(alpha: 0.3)));
        final cuff = RRect.fromRectAndRadius(r(0.28, 0.33, 0.44, 0.08), Radius.circular(0.035 * s));
        canvas.drawRRect(cuff, fill(dark));
        canvas.save();
        canvas.clipRRect(cuff);
        for (var x = 0.3; x < 0.72; x += 0.035) {
          canvas.drawLine(p(x, 0.33), p(x, 0.41), stroke(Colors.black.withValues(alpha: 0.18), 0.008));
        }
        canvas.drawRect(r(0.28, 0.355, 0.44, 0.02), fill(look.accent));
        canvas.restore();
      case Headwear.headband:
        canvas.drawPath(
          Path()
            ..moveTo(0.31 * s, 0.37 * s)
            ..quadraticBezierTo(0.5 * s, 0.31 * s, 0.69 * s, 0.37 * s)
            ..lineTo(0.69 * s, 0.41 * s)
            ..quadraticBezierTo(0.5 * s, 0.35 * s, 0.31 * s, 0.41 * s)
            ..close(),
          fill(c),
        );
        canvas.drawPath(
            Path()
              ..moveTo(0.32 * s, 0.39 * s)
              ..quadraticBezierTo(0.5 * s, 0.333 * s, 0.68 * s, 0.39 * s),
            stroke(look.accent, 0.012));
    }
  }

  @override
  bool shouldRepaint(_PersonPainter old) => old.look != look;
}
