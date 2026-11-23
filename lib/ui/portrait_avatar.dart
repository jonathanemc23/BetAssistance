import 'package:flutter/material.dart';

/// An illustrated portrait avatar: a bettor drawn in a gold ring on a
/// stadium night. Saved as `portrait:<id>`; the id never changes.
class Portrait {
  const Portrait(this.id);
  final String id;
  String get asset => 'assets/avatars/portrait_$id.jpg';
}

/// The portraits the picker offers. Append new ones at the end.
const portraits = <Portrait>[
  Portrait('01'),
];

/// The portrait in an avatar value (`portrait:<id>`), if it is one.
Portrait? portraitOf(String avatar) {
  if (!avatar.startsWith('portrait:')) return null;
  final id = avatar.substring(9);
  for (final p in portraits) {
    if (p.id == id) return p;
  }
  return null;
}

/// Draws a [Portrait] as a circle. The artwork brings its own gold ring, so
/// it is scaled to put that ring at the edge.
class PortraitAvatar extends StatelessWidget {
  const PortraitAvatar({super.key, required this.portrait, this.size = 56});
  final Portrait portrait;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Transform.scale(
            scale: 1.1,
            child: Image.asset(
              portrait.asset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 512),
              errorBuilder: (_, _, _) => Container(color: const Color(0xFF0C0C0E)),
            ),
          ),
        ),
      );
}
