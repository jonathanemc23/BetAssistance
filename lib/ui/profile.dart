import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import '../data/store.dart';
import 'person_avatar.dart';

/// Avatars from before 0.17: an emoji on a coloured disc. Still shown for
/// users who picked one; the picker offers [personLooks] now.
final avatarEmojis = ['⚽', '🏀', '⚾', '🎾', '🦁', '🐺', '🦅', '🐯', '🔥', '⭐', '👑', '🎯'];
final avatarColors = [
  Color(0xFFC5A059),
  Color(0xFF2E9461),
  Color(0xFF3D7DD8),
  Color(0xFFC2402F),
  Color(0xFF8E5BD0),
  Color(0xFF2A9BA5),
];

/// The person preset in an avatar value (`person:<index>`), if it is one.
PersonLook? personOf(String avatar) {
  if (!avatar.startsWith('person:')) return null;
  final i = int.tryParse(avatar.substring(7));
  return i == null || i < 0 || i >= personLooks.length ? null : personLooks[i];
}

/// The user's avatar as chosen in Settings: a preset person, a photo, or
/// their initial (a person icon without a name).
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
    return AvatarImage(avatar: store.avatar, name: store.profileName, size: size);
  }
}

/// Any avatar value drawn as a circle: a preset person, a photo, an older
/// emoji preset, or [name]'s initial.
class AvatarImage extends StatelessWidget {
  const AvatarImage({super.key, required this.avatar, this.name = '', this.size = 56, this.border = true});
  final String avatar;
  final String name;
  final double size;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = avatar;
    final person = personOf(a);
    if (person != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border ? Border.all(color: Colors.white.withValues(alpha: 0.85), width: size / 24) : null,
          boxShadow: border ? const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))] : null,
        ),
        child: PersonAvatar(look: person, size: size),
      );
    }
    final photo = ProfileAvatar.photoOf(a);
    final parts = a.split(':');
    final emoji = parts.length == 3 && parts[0] == 'emoji' ? parts[1] : null;
    final color = emoji == null ? cs.primary : avatarColors[(int.tryParse(parts[2]) ?? 0) % avatarColors.length];
    final initial = name.isEmpty ? null : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
        border: border ? Border.all(color: Colors.white.withValues(alpha: 0.85), width: size / 24) : null,
        boxShadow: border ? const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))] : null,
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

/// The avatar choices: the preset people, a photo from the gallery, or none.
Future<void> showAvatarPicker(BuildContext context, BankStore store) => pickAvatar(
      context,
      current: () => store.avatar,
      name: () => store.profileName,
      listenable: store,
      onPick: store.setAvatar,
    );

/// The avatar picker sheet for any avatar: the profile's or the social
/// profile's. [current] is read on every rebuild of [listenable].
Future<void> pickAvatar(
  BuildContext context, {
  required String Function() current,
  required Listenable listenable,
  required Future<void> Function(String) onPick,
  String Function()? name,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final avatar = current();
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: AvatarImage(avatar: avatar, name: name?.call() ?? '', size: 80)),
                const SizedBox(height: 12),
                Text(tr('Choose your avatar'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
                  for (final (i, look) in personLooks.indexed)
                    () {
                      final value = 'person:$i';
                      final on = avatar == value;
                      return InkWell(
                        key: Key('avatar-$value'),
                        customBorder: const CircleBorder(),
                        onTap: () => onPick(value),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: on ? cs.primary : Colors.transparent, width: 3),
                          ),
                          child: PersonAvatar(look: look, size: 56),
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
                    await onPick('photo:${base64Encode(bytes)}');
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(tr('Use a photo')),
                ),
                if (avatar.isNotEmpty) TextButton(onPressed: () => onPick(''), child: Text(tr('Remove avatar'))),
              ]),
            ),
          );
        },
      ),
    );
