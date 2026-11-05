import 'package:flutter/material.dart';

/// One set of colour values. Light comes from the Resident APP (Phase 1)
/// Figma variables; dark comes from the "Dark Mode" of the same "Semantic
/// Colors" collection in the Keys - Design System V2 library (see
/// docs/design-tokens.md for the full Light/Dark table).
class KPalette {
  const KPalette({
    required this.brightness,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.textLink,
    required this.iconDefault,
    required this.borderDefault,
    required this.borderSubtle,
    required this.borderStrong,
    required this.surfaceDefault,
    required this.surfaceSubtle,
    required this.surfaceMuted,
    required this.surfaceInverted,
    required this.surfaceElevated,
    required this.brand,
    required this.brandSubtle,
    required this.brandMuted,
    required this.success,
    required this.successSubtle,
    required this.error,
    required this.errorSubtle,
    required this.warningSubtle,
    required this.selected,
    required this.selectedSubtle,
    required this.dashed,
    required this.iconMuted,
    required this.iconDisabled,
  });
  final Brightness brightness;
  final Color textPrimary, textSecondary, textTertiary, textInverse, textLink, iconDefault;
  final Color borderDefault, borderSubtle, borderStrong;
  final Color surfaceDefault, surfaceSubtle, surfaceMuted, surfaceInverted, surfaceElevated;
  final Color brand, brandSubtle, brandMuted;
  final Color success, successSubtle, error, errorSubtle, warningSubtle, selected, selectedSubtle, dashed, iconMuted, iconDisabled;

  static const light = KPalette(
    brightness: Brightness.light,
    textPrimary: Color(0xFF171717), // text/default
    textSecondary: Color(0xFF5E5E5E), // Misc/neutral 600
    textTertiary: Color(0xFF8F8F8F),
    textInverse: Color(0xFFFFFFFF), // text/inverse
    textLink: Color(0xFF329CFF), // text/link
    iconDefault: Color(0xFF171717), // icon/default
    borderDefault: Color(0xFFE8E8E8), // border/default
    borderSubtle: Color(0xFFF3F3F3), // border/subtle
    borderStrong: Color(0xFF282828), // border/inverse
    surfaceDefault: Color(0xFFFFFFFF), // surface/default
    surfaceSubtle: Color(0xFFF3F3F3), // surface/subtle
    surfaceMuted: Color(0xFFE8E8E8), // surface/medium
    surfaceInverted: Color(0xFF171717), // surface/inverted
    surfaceElevated: Color(0xFFFFFFFF), // sheets and dialogs
    brand: Color(0xFFFFD12A), // brand/default
    brandSubtle: Color(0xFFFFF9EA), // brand/subtle
    brandMuted: Color(0xFFFFF4CC), // brand/muted
    success: Color(0xFF21AE48), // status/success/default
    successSubtle: Color(0xFFE6F6EA), // status/success/subtle
    error: Color(0xFFD92D20),
    errorSubtle: Color(0xFFFDECEA), // status/error/subtle
    warningSubtle: Color(0xFFFFEDB0),
    selected: Color(0xFF1C8C86), // selected card outline (teal)
    selectedSubtle: Color(0xFFDDF2F0), // secondary/teal/subtle
    dashed: Color(0xFFDDDDDD), // surface/strong, dashed separators
    iconMuted: Color(0xFF868686), // Grey/400: list carets
    iconDisabled: Color(0xFFA6A6A6), // icon/disabled
  );

  static const dark = KPalette(
    brightness: Brightness.dark,
    textPrimary: Color(0xFFF3F3F3),
    textSecondary: Color(0xFFA6A6A6),
    textTertiary: Color(0xFF868686),
    textInverse: Color(0xFF171717),
    textLink: Color(0xFF54ACFF), // secondary/blue/default (dark)
    iconDefault: Color(0xFFE8E8E8),
    borderDefault: Color(0xFF4B4B4B),
    borderSubtle: Color(0xFF282828),
    borderStrong: Color(0xFFE8E8E8),
    surfaceDefault: Color(0xFF171717),
    surfaceSubtle: Color(0xFF282828),
    surfaceMuted: Color(0xFF4B4B4B),
    surfaceInverted: Color(0xFFF3F3F3),
    surfaceElevated: Color(0xFF282828), // surface-page in the app file
    brand: Color(0xFFFFD12A),
    brandSubtle: Color(0xFF332800),
    brandMuted: Color(0xFF7F6400),
    success: Color(0xFF46BB66),
    successSubtle: Color(0xFF0B3A18),
    error: Color(0xFFE96078), // status/error/strong (dark), readable on #171717
    errorSubtle: Color(0xFF4A0612),
    warningSubtle: Color(0xFF4A3200),
    selected: Color(0xFF2A9595),
    selectedSubtle: Color(0xFF001A1A),
    dashed: Color(0xFF5E5E5E),
    iconMuted: Color(0xFF868686),
    iconDisabled: Color(0xFF5E5E5E),
  );
}

/// Colour tokens. Values follow the current [KPalette]; [KTheme] switches it
/// and rebuilds the app.
class KColors {
  static KPalette palette = KPalette.light;
  static bool get isDark => palette.brightness == Brightness.dark;

  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textTertiary => palette.textTertiary;
  static Color get textInverse => palette.textInverse;
  static Color get textLink => palette.textLink;
  static Color get iconDefault => palette.iconDefault;
  static Color get borderDefault => palette.borderDefault;
  static Color get borderSubtle => palette.borderSubtle;
  static Color get borderStrong => palette.borderStrong;
  static Color get surfaceDefault => palette.surfaceDefault;
  static Color get surfaceSubtle => palette.surfaceSubtle;
  static Color get surfaceMuted => palette.surfaceMuted;
  static Color get surfaceInverted => palette.surfaceInverted;
  static Color get surfaceElevated => palette.surfaceElevated;
  static Color get brand => palette.brand;
  static Color get brandSubtle => palette.brandSubtle;
  static Color get brandMuted => palette.brandMuted;
  static Color get success => palette.success;
  static Color get successSubtle => palette.successSubtle;
  static Color get error => palette.error;
  static Color get errorSubtle => palette.errorSubtle;
  static Color get warningSubtle => palette.warningSubtle;
  static Color get selected => palette.selected;
  static Color get selectedSubtle => palette.selectedSubtle;
  static Color get dashed => palette.dashed;
  static Color get iconMuted => palette.iconMuted;
  static Color get iconDisabled => palette.iconDisabled;

  // The same in both modes.
  static const progressStart = Color(0xFFF7931E);
  static const progressEnd = Color(0xFFFFD12A);
  static const scrim = Color(0x99000000);
  /// Text and icons on photos, video and the brand yellow stay as designed.
  static const staticWhite = Color(0xFFFFFFFF);
  static const staticBlack = Color(0xFF171717);
}

class KSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const smPlus = 10.0;
  static const md = 12.0;
  static const mdPlus = 14.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxlPlus = 28.0;
}

class KRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 9999.0;
}

/// Type styles named as in Figma. Colour follows the current palette.
class KText {
  static const _headingMedium = TextStyle(fontFamily: 'Geist', fontSize: 28, fontWeight: FontWeight.w600, height: 36 / 28, letterSpacing: -0.5);
  static const _headingSmall = TextStyle(fontFamily: 'Geist', fontSize: 22, fontWeight: FontWeight.w600, height: 28 / 22, letterSpacing: -0.4);
  static const _headingXSmall = TextStyle(fontFamily: 'Geist', fontSize: 18, fontWeight: FontWeight.w600, height: 24 / 18, letterSpacing: -0.3);
  static const _paragraphLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16, letterSpacing: -0.2);
  static const _paragraphMediumLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500, height: 24 / 16, letterSpacing: -0.2);
  static const _paragraphMedium = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, letterSpacing: -0.1);
  static const _paragraphSmall = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12);
  static const _paragraphMediumSmall = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, height: 16 / 12);
  static const _labelSemibold = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, height: 1, letterSpacing: -0.1);
  static const _overline = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, height: 16 / 11, letterSpacing: 1.0);

  static TextStyle get headingMedium => _headingMedium.copyWith(color: KColors.textPrimary);
  static TextStyle get headingSmall => _headingSmall.copyWith(color: KColors.textPrimary);
  static TextStyle get headingXSmall => _headingXSmall.copyWith(color: KColors.textPrimary);
  static TextStyle get paragraphLarge => _paragraphLarge.copyWith(color: KColors.textPrimary);
  static TextStyle get paragraphMediumLarge => _paragraphMediumLarge.copyWith(color: KColors.textPrimary);
  static TextStyle get paragraphMedium => _paragraphMedium.copyWith(color: KColors.textPrimary);
  static TextStyle get paragraphSmall => _paragraphSmall.copyWith(color: KColors.textPrimary);
  static TextStyle get paragraphMediumSmall => _paragraphMediumSmall.copyWith(color: KColors.textPrimary);
  static TextStyle get labelSemibold => _labelSemibold.copyWith(color: KColors.textPrimary);
  static TextStyle get overline => _overline.copyWith(color: KColors.textSecondary);
}

/// Page background: white fading to brand-subtle (Figma 182deg gradient).
LinearGradient get kPageGradient => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [KColors.surfaceDefault, KColors.brandSubtle],
    );
