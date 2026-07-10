import 'package:flutter/material.dart';

/// Shared design tokens for the Moonlight TV presentation layer.
abstract final class MoonlightColors {
  static const background = Color(0xFF282C38);
  static const header = Color(0xFF333846);
  static const surface = Color(0xFF3E4454);
  static const control = Color(0xFF404354);
  static const controlFocused = Color(0xFF484C5F);
  static const input = Color(0xFF585D75);
  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFCFCFCF);
  static const textBody = Color(0xFFECECEC);
  static const cyan = Color(0xFF00A3C6);
  static const offline = Color(0xFFF44336);
  static const running = Color(0xFF8BC34A);
  static const warning = Color(0xFFEFC004);
  static const divider = Color(0xFF545B6A);
}

abstract final class MoonlightMetrics {
  static const referenceWidth = 1920.0;
  static const referenceHeight = 1080.0;
  static const headerHeight = 80.0;
  static const tvGutter = 80.0;
  static const compactGutter = 24.0;
  static const narrowBreakpoint = 900.0;
  static const cardFocusScale = 1.2;
  static const controlRadius = 8.0;
  static const dialogRadius = 16.0;

  static double horizontalGutter(double width) {
    if (width >= 1280) return tvGutter;
    if (width >= 700) return 40;
    return compactGutter;
  }

  static int hostColumns(double availableWidth) {
    return ((availableWidth + 36) / (285 + 36)).floor().clamp(1, 5);
  }

  static int appColumns(double availableWidth) {
    return ((availableWidth + 32) / (235 + 32)).floor().clamp(1, 6);
  }
}

ThemeData buildMoonlightTheme() {
  const colorScheme = ColorScheme.dark(
    primary: MoonlightColors.cyan,
    secondary: MoonlightColors.cyan,
    surface: MoonlightColors.surface,
    error: MoonlightColors.offline,
    onPrimary: MoonlightColors.text,
    onSecondary: MoonlightColors.text,
    onSurface: MoonlightColors.text,
    onError: MoonlightColors.text,
  );

  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: MoonlightColors.background,
    fontFamily: 'Roboto',
    useMaterial3: true,
  );

  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    dividerColor: MoonlightColors.divider,
    textTheme: base.textTheme.copyWith(
      displaySmall: const TextStyle(
        color: MoonlightColors.textMuted,
        fontSize: 42,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
      headlineMedium: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 32,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
      titleLarge: const TextStyle(
        color: MoonlightColors.textMuted,
        fontSize: 27,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
      titleMedium: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
      bodyLarge: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 22,
        height: 1.35,
        letterSpacing: .5,
      ),
      bodyMedium: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 18,
        height: 1.4,
        letterSpacing: .35,
      ),
      labelLarge: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MoonlightColors.header,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(MoonlightMetrics.dialogRadius),
        ),
        side: BorderSide(color: MoonlightColors.cyan, width: 2),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MoonlightColors.cyan,
      linearTrackColor: MoonlightColors.control,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xE63E4454),
      contentTextStyle: TextStyle(
        color: MoonlightColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: MoonlightColors.cyan, width: 2),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: MoonlightColors.input,
      labelStyle: TextStyle(color: MoonlightColors.textMuted, fontSize: 20),
      hintStyle: TextStyle(color: Color(0x99FFFFFF), fontSize: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: Color(0x33FFFFFF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: MoonlightColors.cyan, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: MoonlightColors.offline, width: 2),
      ),
    ),
  );
}
