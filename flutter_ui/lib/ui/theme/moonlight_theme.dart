import 'package:flutter/material.dart';

/// Shared design tokens for the Moonlight TV presentation layer.
abstract final class MoonlightColors {
  // Material dark surfaces with the cool blue cast used in the reference UI.
  static const background = Color(0xFF0A1019);
  static const header = Color(0xFF111318);
  static const surface = Color(0xFF1B1F24);
  static const surfaceRaised = Color(0xFF22272E);
  static const control = Color(0xFF252A31);
  static const controlFocused = Color(0xFF46536A);
  static const input = Color(0xFF20252C);
  static const text = Color(0xFFF1F2F6);
  static const textMuted = Color(0xFFC6CAD3);
  static const textBody = Color(0xFFE1E3E9);
  static const cyan = Color(0xFF9EC5FE);
  static const onCyan = Color(0xFF003258);
  static const offline = Color(0xFFF44336);
  static const running = Color(0xFF8BC34A);
  static const warning = Color(0xFFEFC004);
  static const divider = Color(0xFF303844);
}

abstract final class MoonlightMetrics {
  static const referenceWidth = 1920.0;
  static const referenceHeight = 1080.0;
  static const headerHeight = 72.0;
  static const tvGutter = 32.0;
  static const compactGutter = 20.0;
  static const narrowBreakpoint = 900.0;
  static const cardFocusScale = 1.025;
  static const controlRadius = 12.0;
  static const dialogRadius = 24.0;
  static const minHitTarget = 64.0;
  static const focusStroke = 4.0;

  static double horizontalGutter(double width) {
    if (width >= 1280) return tvGutter;
    if (width >= 700) return 24;
    return compactGutter;
  }

  static int hostColumns(double availableWidth) {
    return ((availableWidth + 24) / (360 + 24)).floor().clamp(1, 4);
  }

  static int appColumns(double availableWidth) {
    return ((availableWidth + 28) / (300 + 28)).floor().clamp(1, 5);
  }
}

ThemeData buildMoonlightTheme() {
  const colorScheme = ColorScheme.dark(
    primary: MoonlightColors.cyan,
    secondary: MoonlightColors.cyan,
    surface: MoonlightColors.surface,
    error: MoonlightColors.offline,
    onPrimary: MoonlightColors.onCyan,
    onSecondary: MoonlightColors.onCyan,
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
    splashFactory: InkSparkle.splashFactory,
    dividerColor: MoonlightColors.divider,
    textTheme: base.textTheme.copyWith(
      displaySmall: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 24,
        fontWeight: FontWeight.w500,
        letterSpacing: .15,
      ),
      headlineMedium: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 32,
        fontWeight: FontWeight.w400,
      ),
      titleLarge: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: .15,
      ),
      titleMedium: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
      bodyLarge: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 20,
        height: 1.4,
        letterSpacing: .15,
      ),
      bodyMedium: const TextStyle(
        color: MoonlightColors.textBody,
        fontSize: 17,
        height: 1.4,
        letterSpacing: .35,
      ),
      labelLarge: const TextStyle(
        color: MoonlightColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MoonlightColors.surface,
      surfaceTintColor: MoonlightColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(MoonlightMetrics.dialogRadius),
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MoonlightColors.cyan,
      linearTrackColor: MoonlightColors.control,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MoonlightColors.surface,
      contentTextStyle: TextStyle(
        color: MoonlightColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: MoonlightColors.input,
      labelStyle: TextStyle(color: MoonlightColors.textMuted, fontSize: 18),
      hintStyle: TextStyle(color: Color(0x99FFFFFF), fontSize: 18),
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
    cardTheme: const CardThemeData(
      color: MoonlightColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MoonlightColors.header,
      foregroundColor: MoonlightColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
      toolbarHeight: MoonlightMetrics.headerHeight,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF0D4775)
            : MoonlightColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MoonlightColors.cyan
            : MoonlightColors.controlFocused,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: MoonlightColors.cyan,
      inactiveTrackColor: MoonlightColors.controlFocused,
      disabledActiveTrackColor: MoonlightColors.textMuted,
      disabledInactiveTrackColor: MoonlightColors.control,
      thumbColor: MoonlightColors.cyan,
      overlayColor: Color(0x339EC5FE),
      trackHeight: 5,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, MoonlightMetrics.minHitTarget),
        padding: const EdgeInsets.symmetric(horizontal: 28),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, MoonlightMetrics.minHitTarget),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: MoonlightMetrics.minHitTarget,
      iconColor: MoonlightColors.textMuted,
      textColor: MoonlightColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
  );
}
