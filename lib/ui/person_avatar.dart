import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a preset person avatar looks: skin, hair, clothes and extras.
enum HairStyle { short, buzz, curly, long, bun, ponytail, bald, quiff, bob }

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
  });
  final Color skin;
  final HairStyle hair;
  final Color hairColor;
  final Color shirt;
  final Color background;
  final bool beard;
  final bool glasses;
  final bool earrings;
}

const _black = Color(0xFF241A14), _brown = Color(0xFF5A3825), _blond = Color(0xFFD8A64A), _red = Color(0xFFA4452A);
const _grey = Color(0xFFB9B4AE);

/// The preset people, saved as `person:<index>`.
const personLooks = <PersonLook>[
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.short, hairColor: _brown, shirt: Color(0xFF2E9461), background: Color(0xFFCFE8D9)),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.long, hairColor: _blond, shirt: Color(0xFF8E5BD0), background: Color(0xFFE6DAF6), earrings: true),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.curly, hairColor: _black, shirt: Color(0xFFE0A93B), background: Color(0xFFF6E3BC)),
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.bun, hairColor: _black, shirt: Color(0xFFC2402F), background: Color(0xFFF5D4CE), earrings: true),
  PersonLook(skin: Color(0xFF9E6640), hair: HairStyle.buzz, hairColor: _black, shirt: Color(0xFF3D7DD8), background: Color(0xFFD3E2F7), beard: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.quiff, hairColor: _red, shirt: Color(0xFF2A9BA5), background: Color(0xFFCFEDEF), glasses: true),
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.ponytail, hairColor: _brown, shirt: Color(0xFF2E9461), background: Color(0xFFE2EFD0)),
  PersonLook(skin: Color(0xFFC98E62), hair: HairStyle.bald, hairColor: _black, shirt: Color(0xFF35424F), background: Color(0xFFD9DEE3), beard: true),
  PersonLook(skin: Color(0xFF6E4429), hair: HairStyle.bob, hairColor: _black, shirt: Color(0xFFD9467A), background: Color(0xFFF7D6E2), glasses: true),
  PersonLook(skin: Color(0xFFF6D3B3), hair: HairStyle.short, hairColor: _grey, shirt: Color(0xFF6B4D16), background: Color(0xFFEDE3CF), glasses: true, beard: true),
  PersonLook(skin: Color(0xFF9E6640), hair: HairStyle.long, hairColor: _black, shirt: Color(0xFF3D7DD8), background: Color(0xFFDCE4F9)),
  PersonLook(skin: Color(0xFFE8B98F), hair: HairStyle.curly, hairColor: _blond, shirt: Color(0xFFC2402F), background: Color(0xFFF8DCCB)),
];

/// Draws a [PersonLook] as a round, flat illustration: background, shoulders,
/// head, hair and face.
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

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Rect r(double l, double t, double w, double h) => Rect.fromLTWH(l * s, t * s, w * s, h * s);
    final fill = Paint()..isAntiAlias = true;
    final skin = look.skin, shade = Color.lerp(skin, Colors.black, 0.14)!;
    final hair = look.hairColor, hairDark = Color.lerp(hair, Colors.black, 0.25)!;

    canvas.save();
    canvas.clipPath(Path()..addOval(r(0, 0, 1, 1)));
    // Background with a soft light from the top.
    canvas.drawRect(
      r(0, 0, 1, 1),
      fill
        ..shader = RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 0.9,
          colors: [Color.lerp(look.background, Colors.white, 0.35)!, look.background],
        ).createShader(r(0, 0, 1, 1)),
    );
    fill.shader = null;
    // The person fills more of the circle than the unit drawing below.
    canvas.translate(0.5 * s, 0.6 * s);
    canvas.scale(1.2);
    canvas.translate(-0.5 * s, -0.6 * s);

    // Hair that falls behind the head and shoulders.
    fill.color = hair;
    switch (look.hair) {
      case HairStyle.long:
        canvas.drawRRect(RRect.fromRectAndRadius(r(0.26, 0.2, 0.48, 0.6), Radius.circular(0.2 * s)), fill);
      case HairStyle.bob:
        canvas.drawRRect(RRect.fromRectAndRadius(r(0.25, 0.2, 0.5, 0.42), Radius.circular(0.16 * s)), fill);
      case HairStyle.ponytail:
        canvas.drawOval(r(0.64, 0.3, 0.16, 0.34), fill);
      case HairStyle.curly:
        for (final (x, y, rad) in [
          (0.29, 0.38, 0.085), (0.71, 0.38, 0.085), (0.27, 0.5, 0.07), (0.73, 0.5, 0.07),
        ]) {
          canvas.drawCircle(p(x, y), rad * s, fill);
        }
      default:
        break;
    }

    // Shoulders and shirt, with a collar of skin.
    fill.color = look.shirt;
    canvas.drawOval(r(0.12, 0.74, 0.76, 0.56), fill);
    fill.color = Color.lerp(look.shirt, Colors.black, 0.18)!;
    canvas.drawPath(
      Path()
        ..moveTo(0.39 * s, 0.76 * s)
        ..quadraticBezierTo(0.5 * s, 0.9 * s, 0.61 * s, 0.76 * s)
        ..lineTo(0.58 * s, 0.75 * s)
        ..quadraticBezierTo(0.5 * s, 0.84 * s, 0.42 * s, 0.75 * s)
        ..close(),
      fill,
    );
    // Neck.
    fill.color = shade;
    canvas.drawRRect(RRect.fromRectAndRadius(r(0.42, 0.58, 0.16, 0.2), Radius.circular(0.06 * s)), fill);
    fill.color = skin;
    canvas.drawPath(
      Path()
        ..moveTo(0.42 * s, 0.74 * s)
        ..quadraticBezierTo(0.5 * s, 0.82 * s, 0.58 * s, 0.74 * s)
        ..lineTo(0.58 * s, 0.77 * s)
        ..quadraticBezierTo(0.5 * s, 0.86 * s, 0.42 * s, 0.77 * s)
        ..close(),
      fill,
    );

    // Ears, then the head.
    fill.color = shade;
    canvas.drawOval(r(0.275, 0.42, 0.08, 0.11), fill);
    canvas.drawOval(r(0.645, 0.42, 0.08, 0.11), fill);
    if (look.earrings) {
      fill.color = const Color(0xFFF2C94C);
      canvas.drawCircle(p(0.305, 0.55), 0.018 * s, fill);
      canvas.drawCircle(p(0.695, 0.55), 0.018 * s, fill);
    }
    fill.color = skin;
    canvas.drawOval(r(0.31, 0.24, 0.38, 0.42), fill);

    // Beard along the jaw.
    if (look.beard) {
      fill.color = hairDark;
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
        fill,
      );
    }

    // Hair on top of the head.
    fill.color = hair;
    final cap = Path()
      ..moveTo(0.3 * s, 0.44 * s)
      ..cubicTo(0.27 * s, 0.2 * s, 0.73 * s, 0.2 * s, 0.7 * s, 0.44 * s)
      ..quadraticBezierTo(0.66 * s, 0.33 * s, 0.56 * s, 0.32 * s)
      ..quadraticBezierTo(0.42 * s, 0.31 * s, 0.36 * s, 0.36 * s)
      ..quadraticBezierTo(0.32 * s, 0.39 * s, 0.3 * s, 0.44 * s)
      ..close();
    switch (look.hair) {
      case HairStyle.short:
        canvas.drawPath(cap, fill);
      case HairStyle.buzz:
        canvas.drawPath(
          Path()
            ..moveTo(0.31 * s, 0.4 * s)
            ..cubicTo(0.31 * s, 0.2 * s, 0.69 * s, 0.2 * s, 0.69 * s, 0.4 * s)
            ..quadraticBezierTo(0.5 * s, 0.3 * s, 0.31 * s, 0.4 * s)
            ..close(),
          fill..color = hair.withValues(alpha: 0.85),
        );
      case HairStyle.curly:
        for (final (x, y, rad) in [
          (0.34, 0.31, 0.08), (0.43, 0.25, 0.085), (0.53, 0.24, 0.085), (0.62, 0.28, 0.08), (0.68, 0.36, 0.065),
          (0.32, 0.38, 0.06), (0.5, 0.3, 0.07),
        ]) {
          canvas.drawCircle(p(x, y), rad * s, fill);
        }
      case HairStyle.long || HairStyle.bob:
        canvas.drawPath(
          Path()
            ..moveTo(0.3 * s, 0.5 * s)
            ..cubicTo(0.26 * s, 0.18 * s, 0.74 * s, 0.18 * s, 0.7 * s, 0.5 * s)
            ..quadraticBezierTo(0.66 * s, 0.34 * s, 0.5 * s, 0.31 * s)
            ..quadraticBezierTo(0.36 * s, 0.33 * s, 0.3 * s, 0.5 * s)
            ..close(),
          fill,
        );
      case HairStyle.bun:
        canvas.drawCircle(p(0.5, 0.2), 0.08 * s, fill);
        canvas.drawPath(cap, fill);
      case HairStyle.ponytail:
        canvas.drawPath(cap, fill);
        fill.color = hairDark;
        canvas.drawCircle(p(0.68, 0.33), 0.025 * s, fill);
      case HairStyle.quiff:
        canvas.drawPath(cap, fill);
        canvas.drawPath(
          Path()
            ..moveTo(0.38 * s, 0.3 * s)
            ..quadraticBezierTo(0.46 * s, 0.13 * s, 0.66 * s, 0.22 * s)
            ..quadraticBezierTo(0.56 * s, 0.24 * s, 0.6 * s, 0.31 * s)
            ..close(),
          fill,
        );
      case HairStyle.bald:
        fill.color = hair.withValues(alpha: 0.75);
        canvas.drawOval(r(0.3, 0.38, 0.05, 0.08), fill);
        canvas.drawOval(r(0.65, 0.38, 0.05, 0.08), fill);
        fill.color = Colors.white.withValues(alpha: 0.18);
        canvas.drawOval(r(0.42, 0.27, 0.12, 0.05), fill);
    }

    // Face: brows, eyes, nose, cheeks and a smile.
    final line = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    line
      ..color = hairDark
      ..strokeWidth = 0.022 * s;
    canvas.drawLine(p(0.39, 0.415), p(0.46, 0.405), line);
    canvas.drawLine(p(0.54, 0.405), p(0.61, 0.415), line);
    fill.color = const Color(0xFF2B211B);
    canvas.drawCircle(p(0.425, 0.46), 0.022 * s, fill);
    canvas.drawCircle(p(0.575, 0.46), 0.022 * s, fill);
    fill.color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(p(0.432, 0.453), 0.007 * s, fill);
    canvas.drawCircle(p(0.582, 0.453), 0.007 * s, fill);
    line
      ..color = shade
      ..strokeWidth = 0.018 * s;
    canvas.drawArc(r(0.475, 0.47, 0.05, 0.05), 0.2, math.pi * 0.6, false, line);
    fill.color = const Color(0xFFE5776B).withValues(alpha: 0.25);
    canvas.drawCircle(p(0.38, 0.52), 0.03 * s, fill);
    canvas.drawCircle(p(0.62, 0.52), 0.03 * s, fill);
    line
      ..color = const Color(0xFF8C3B32)
      ..strokeWidth = 0.02 * s;
    canvas.drawArc(r(0.44, 0.5, 0.12, 0.07), 0.25, math.pi - 0.5, false, line);

    if (look.glasses) {
      line
        ..color = const Color(0xFF2B2B2B)
        ..strokeWidth = 0.016 * s;
      canvas.drawRRect(RRect.fromRectAndRadius(r(0.375, 0.425, 0.1, 0.075), Radius.circular(0.025 * s)), line);
      canvas.drawRRect(RRect.fromRectAndRadius(r(0.525, 0.425, 0.1, 0.075), Radius.circular(0.025 * s)), line);
      canvas.drawLine(p(0.475, 0.455), p(0.525, 0.455), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PersonPainter old) => old.look != look;
}
