import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'phosphor.dart';
import 'tokens.dart';

/// Material theme built from the current [KColors.palette] (light or dark).
ThemeData buildTheme() {
  final dark = KColors.isDark;
  final base = ThemeData(useMaterial3: true, fontFamily: 'Inter', brightness: dark ? Brightness.dark : Brightness.light);
  return base.copyWith(
    scaffoldBackgroundColor: KColors.surfaceDefault,
    canvasColor: KColors.surfaceDefault,
    dividerColor: KColors.borderDefault,
    colorScheme: base.colorScheme.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: KColors.surfaceInverted,
      onPrimary: KColors.textInverse,
      secondary: KColors.brand,
      onSecondary: KColors.staticBlack,
      surface: KColors.surfaceDefault,
      onSurface: KColors.textPrimary,
      onSurfaceVariant: KColors.textSecondary,
      surfaceContainerHighest: KColors.surfaceSubtle,
      surfaceContainerHigh: KColors.surfaceElevated,
      surfaceContainer: KColors.surfaceElevated,
      surfaceContainerLow: KColors.surfaceElevated,
      outline: KColors.borderDefault,
      outlineVariant: KColors.borderSubtle,
      error: KColors.error,
    ),
    iconTheme: IconThemeData(color: KColors.iconDefault),
    appBarTheme: AppBarTheme(
      backgroundColor: KColors.surfaceDefault,
      foregroundColor: KColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    dividerTheme: DividerThemeData(color: KColors.borderDefault, space: 1, thickness: 1),
    dialogTheme: DialogThemeData(backgroundColor: KColors.surfaceElevated, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: KColors.surfaceElevated, surfaceTintColor: Colors.transparent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: KColors.textPrimary),
    // Back and close buttons Flutter draws itself use the design's Phosphor icons.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.caretLeft, size: 26),
      closeButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.x, size: 24),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: KColors.textPrimary),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KColors.surfaceInverted,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: KColors.textInverse, fontSize: 14),
    ),
    // Grey pills as in the design (role chips, board tabs, filters).
    chipTheme: ChipThemeData(
      backgroundColor: KColors.surfaceSubtle,
      selectedColor: KColors.surfaceInverted,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: KColors.textPrimary),
      secondaryLabelStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: KColors.textInverse),
      showCheckmark: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: KColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KRadius.lg))),
      showDragHandle: true,
    ),
  );
}
