import 'package:flutter/material.dart';

/// Design tokens from the Resident APP (Phase 1) Figma variables.
class KColors {
  static const textPrimary = Color(0xFF171717);
  static const textSecondary = Color(0xFF5E5E5E);
  static const textTertiary = Color(0xFF8F8F8F);
  static const textInverse = Color(0xFFFFFFFF);
  static const textLink = Color(0xFF329CFF);
  static const iconDefault = Color(0xFF171717);
  static const borderDefault = Color(0xFFE8E8E8);
  static const borderStrong = Color(0xFF282828);
  static const surfaceDefault = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF3F3F3);
  static const surfaceMuted = Color(0xFFE8E8E8);
  static const surfaceInverted = Color(0xFF171717);
  static const brand = Color(0xFFFFD12A);
  static const brandSubtle = Color(0xFFFFF9EA);
  static const success = Color(0xFF21AE48);
  static const error = Color(0xFFD92D20);
  static const selected = Color(0xFF1C8C86); // selected card outline (home type cards)
  static const progressStart = Color(0xFFF7931E);
  static const progressEnd = Color(0xFFFFD12A);
  static const scrim = Color(0x99000000);
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

/// Type styles named as in Figma.
class KText {
  static const headingMedium = TextStyle(fontFamily: 'Geist', fontSize: 28, fontWeight: FontWeight.w600, height: 36 / 28, letterSpacing: -0.5, color: KColors.textPrimary);
  static const headingSmall = TextStyle(fontFamily: 'Geist', fontSize: 22, fontWeight: FontWeight.w600, height: 28 / 22, letterSpacing: -0.4, color: KColors.textPrimary);
  static const headingXSmall = TextStyle(fontFamily: 'Geist', fontSize: 18, fontWeight: FontWeight.w600, height: 24 / 18, letterSpacing: -0.3, color: KColors.textPrimary);
  static const paragraphLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16, letterSpacing: -0.2, color: KColors.textPrimary);
  static const paragraphMediumLarge = TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w500, height: 24 / 16, letterSpacing: -0.2, color: KColors.textPrimary);
  static const paragraphMedium = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14, letterSpacing: -0.1, color: KColors.textPrimary);
  static const paragraphSmall = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w400, height: 16 / 12, color: KColors.textPrimary);
  static const paragraphMediumSmall = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500, height: 16 / 12, color: KColors.textPrimary);
  static const labelSemibold = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, height: 1, letterSpacing: -0.1, color: KColors.textPrimary);
  static const overline = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, height: 16 / 11, letterSpacing: 1.0, color: KColors.textSecondary);
}

/// Page background: white fading to brand-subtle (Figma 182deg gradient).
const kPageGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [KColors.surfaceDefault, KColors.brandSubtle],
);
