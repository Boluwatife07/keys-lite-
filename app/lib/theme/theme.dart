import 'package:flutter/material.dart';
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
    textSelectionTheme: const TextSelectionThemeData(cursorColor: KColors.textPrimary),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KColors.surfaceInverted,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: KColors.textInverse, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surfaceDefault,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KRadius.lg))),
      showDragHandle: true,
    ),
  );
}
