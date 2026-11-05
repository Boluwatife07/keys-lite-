import 'package:flutter/material.dart';
import 'phosphor.dart';
import 'tokens.dart';

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, fontFamily: 'Inter');
  return base.copyWith(
    scaffoldBackgroundColor: KColors.surfaceDefault,
    colorScheme: base.colorScheme.copyWith(
      primary: KColors.surfaceInverted,
      onPrimary: KColors.textInverse,
      secondary: KColors.brand,
      surface: KColors.surfaceDefault,
      error: KColors.error,
    ),
    // Back and close buttons Flutter draws itself use the design's Phosphor icons.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.caretLeft, size: 26),
      closeButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.x, size: 24),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: KColors.textPrimary),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KColors.surfaceInverted,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: KColors.textInverse, fontSize: 14),
    ),
    // Grey pills as in the design (role chips, board tabs, filters).
    chipTheme: const ChipThemeData(
      backgroundColor: KColors.surfaceSubtle,
      selectedColor: KColors.surfaceInverted,
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: KColors.textPrimary),
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: KColors.textInverse),
      showCheckmark: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KRadius.lg))),
      showDragHandle: true,
    ),
  );
}
