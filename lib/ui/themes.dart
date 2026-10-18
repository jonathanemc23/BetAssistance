import 'package:flutter/material.dart';

/// One of the looks the user can pick in Settings. Colours are explicit so
/// each theme matches its palette exactly instead of a generated one.
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.brightness,
    required this.background,
    required this.cardLowest,
    required this.card,
    required this.cardMid,
    required this.cardHigh,
    required this.cardHighest,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.hero,
    required this.onHero,
  });

  final String id;
  final String name;
  final String description;
  final Brightness brightness;
  final Color background;
  final Color cardLowest, card, cardMid, cardHigh, cardHighest;
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;
  final Color secondary, secondaryContainer, onSecondaryContainer, tertiary;
  final Color onSurface, onSurfaceVariant, outline, outlineVariant;

  /// Gradient for headers (bet slip, bankroll card) and the text on it.
  final List<Color> hero;
  final Color onHero;

  /// Swatches shown in the theme picker.
  List<Color> get swatches => [background, card, primary, secondary];

  ThemeData data() {
    final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      surface: background,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      surfaceContainerLowest: cardLowest,
      surfaceContainerLow: card,
      surfaceContainer: cardMid,
      surfaceContainerHigh: cardHigh,
      surfaceContainerHighest: cardHighest,
      outline: outline,
      outlineVariant: outlineVariant,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardLowest,
        indicatorColor: secondaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(elevation: 0, color: card),
      dialogTheme: DialogThemeData(backgroundColor: cardMid),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: cardMid, surfaceTintColor: Colors.transparent),
      extensions: [HeroColors(hero, onHero)],
    );
  }
}

/// Header gradient for the current theme: `HeroColors.of(context)`.
class HeroColors extends ThemeExtension<HeroColors> {
  const HeroColors(this.gradient, this.onGradient);
  final List<Color> gradient;
  final Color onGradient;

  static HeroColors of(BuildContext context) =>
      Theme.of(context).extension<HeroColors>() ??
      const HeroColors([Color(0xFF1D6B45), Color(0xFF2E9461)], Colors.white);

  @override
  HeroColors copyWith({List<Color>? gradient, Color? onGradient}) =>
      HeroColors(gradient ?? this.gradient, onGradient ?? this.onGradient);

  @override
  HeroColors lerp(HeroColors? other, double t) {
    if (other == null) return this;
    return HeroColors([
      for (var i = 0; i < gradient.length; i++) Color.lerp(gradient[i], other.gradient[i], t)!,
    ], Color.lerp(onGradient, other.onGradient, t)!);
  }
}

const appThemes = <AppTheme>[
  // Laura's palette: dark olive with classic, champagne and aged gold.
  AppTheme(
    id: 'olive',
    name: 'Olive & Gold',
    description: 'Dark olive with gold accents',
    brightness: Brightness.dark,
    background: Color(0xFF171B13),
    cardLowest: Color(0xFF12150F),
    card: Color(0xFF262E1F),
    cardMid: Color(0xFF2D3625),
    cardHigh: Color(0xFF343F2A),
    cardHighest: Color(0xFF3E4A33),
    primary: Color(0xFFC5A059),
    onPrimary: Color(0xFF1A1508),
    primaryContainer: Color(0xFF4A3D1E),
    onPrimaryContainer: Color(0xFFE2C786),
    secondary: Color(0xFFE2C786),
    secondaryContainer: Color(0xFF4A3D1E),
    onSecondaryContainer: Color(0xFFE2C786),
    tertiary: Color(0xFF8C6B2F),
    onSurface: Color(0xFFEEE8D6),
    onSurfaceVariant: Color(0xFFB8B29B),
    outline: Color(0xFF7A7560),
    outlineVariant: Color(0xFF3E4A33),
    hero: [Color(0xFF343F2A), Color(0xFF1C2217)],
    onHero: Color(0xFFE2C786),
  ),
  AppTheme(
    id: 'carbon',
    name: 'Carbon',
    description: 'True black with silver, easy on OLED screens',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    cardLowest: Color(0xFF0A0A0A),
    card: Color(0xFF141414),
    cardMid: Color(0xFF1B1B1B),
    cardHigh: Color(0xFF232323),
    cardHighest: Color(0xFF2C2C2C),
    primary: Color(0xFFF2F2F2),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF2E2E2E),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFBDBDBD),
    secondaryContainer: Color(0xFF333333),
    onSecondaryContainer: Color(0xFFFFFFFF),
    tertiary: Color(0xFF8A8A8A),
    onSurface: Color(0xFFF5F5F5),
    onSurfaceVariant: Color(0xFFA6A6A6),
    outline: Color(0xFF6B6B6B),
    outlineVariant: Color(0xFF2E2E2E),
    hero: [Color(0xFF2A2A2A), Color(0xFF0B0B0B)],
    onHero: Color(0xFFFFFFFF),
  ),
  AppTheme(
    id: 'ember',
    name: 'Ember',
    description: 'Warm dark with red and orange',
    brightness: Brightness.dark,
    background: Color(0xFF160F0D),
    cardLowest: Color(0xFF110B09),
    card: Color(0xFF261813),
    cardMid: Color(0xFF2E1D17),
    cardHigh: Color(0xFF38241C),
    cardHighest: Color(0xFF432B22),
    primary: Color(0xFFFF6A3D),
    onPrimary: Color(0xFF1C0C06),
    primaryContainer: Color(0xFF5A2615),
    onPrimaryContainer: Color(0xFFFFD2C2),
    secondary: Color(0xFFFFA94D),
    secondaryContainer: Color(0xFF4F2A16),
    onSecondaryContainer: Color(0xFFFFD9B0),
    tertiary: Color(0xFFFFC46B),
    onSurface: Color(0xFFF7E9E3),
    onSurfaceVariant: Color(0xFFC4A99F),
    outline: Color(0xFF85695F),
    outlineVariant: Color(0xFF432B22),
    hero: [Color(0xFFD63A22), Color(0xFFFF8A3D)],
    onHero: Color(0xFFFFFFFF),
  ),
  AppTheme(
    id: 'ocean',
    name: 'Ocean',
    description: 'Light and clean with blue',
    brightness: Brightness.light,
    background: Color(0xFFF3F6FB),
    cardLowest: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardMid: Color(0xFFEDF2F9),
    cardHigh: Color(0xFFE5ECF6),
    cardHighest: Color(0xFFDBE4F1),
    primary: Color(0xFF1F5FD6),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD8E5FF),
    onPrimaryContainer: Color(0xFF0B2E6E),
    secondary: Color(0xFF3FA2F7),
    secondaryContainer: Color(0xFFD8E5FF),
    onSecondaryContainer: Color(0xFF0B2E6E),
    tertiary: Color(0xFF00A3A3),
    onSurface: Color(0xFF0F1B2D),
    onSurfaceVariant: Color(0xFF52607A),
    outline: Color(0xFF8A97AD),
    outlineVariant: Color(0xFFD2DAE6),
    hero: [Color(0xFF1F5FD6), Color(0xFF3FA2F7)],
    onHero: Color(0xFFFFFFFF),
  ),
];

AppTheme themeById(String? id) => appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);
