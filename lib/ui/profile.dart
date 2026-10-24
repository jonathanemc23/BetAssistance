import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../data/store.dart';

/// The preset avatars: an emoji on a coloured disc.
final avatarEmojis = ['⚽', '🏀', '⚾', '🎾', '🦁', '🐺', '🦅', '🐯', '🔥', '⭐', '👑', '🎯'];
final avatarColors = [
  Color(0xFFC5A059),
  Color(0xFF2E9461),
  Color(0xFF3D7DD8),
  Color(0xFFC2402F),
  Color(0xFF8E5BD0),
  Color(0xFF2A9BA5),
];

/// The user's avatar as chosen in Settings: a preset, a photo, or their
/// initial (a person icon without a name).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.store, this.size = 56});
  final BankStore store;
  final double size;

  static final _photos = <String, MemoryImage>{};

  /// The photo for a `photo:` avatar, decoded once.
  static MemoryImage? photoOf(String avatar) {
    if (!avatar.startsWith('photo:')) return null;
    return _photos.putIfAbsent(avatar, () {
      if (_photos.length > 4) _photos.clear();
      return MemoryImage(base64Decode(avatar.substring(6)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = store.avatar;
    final photo = photoOf(a);
    final parts = a.split(':');
    final emoji = parts.length == 3 && parts[0] == 'emoji' ? parts[1] : null;
    final color = emoji == null ? cs.primary : avatarColors[(int.tryParse(parts[2]) ?? 0) % avatarColors.length];
    final initial = store.profileName.isEmpty ? null : store.profileName.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: size / 24),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: photo != null
          ? null
          : emoji != null
              ? Text(emoji, style: TextStyle(fontSize: size * 0.48))
              : initial != null
                  ? Text(initial,
                      style: TextStyle(color: cs.onPrimary, fontSize: size * 0.44, fontWeight: FontWeight.w800))
                  : Icon(Icons.person, color: cs.onPrimary, size: size * 0.56),
    );
  }
}

/// Picks a photo for the avatar; tests replace it. Returns the image's path.
Future<String?> Function() pickAvatarPhoto = () async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 80);
  return f?.path;
};

/// The avatar choices: the presets, a photo from the gallery, or none.
Future<void> showAvatarPicker(BuildContext context, BankStore store) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: ProfileAvatar(store: store, size: 80)),
                const SizedBox(height: 12),
                Text(tr('Choose your avatar'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                  for (final (i, e) in avatarEmojis.indexed)
                    () {
                      final value = 'emoji:$e:${i % avatarColors.length}';
                      final on = store.avatar == value;
                      return InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => store.setAvatar(value),
                        child: Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColors[i % avatarColors.length],
                            border: Border.all(color: on ? cs.onSurface : Colors.transparent, width: 3),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }(),
                ]),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final path = await pickAvatarPhoto();
                    if (path == null) return;
                    final bytes = await File(path).readAsBytes();
                    await store.setAvatar('photo:${base64Encode(bytes)}');
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(tr('Use a photo')),
                ),
                if (store.avatar.isNotEmpty)
                  TextButton(onPressed: () => store.setAvatar(''), child: Text(tr('Remove avatar'))),
              ]),
            ),
          );
        },
      ),
    );
