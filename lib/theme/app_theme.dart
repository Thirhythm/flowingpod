import 'package:flowingpod/core/models/app_theme_mode.dart';
import 'package:flutter/material.dart';

/// Material 3 theme built around a blue brand seed.
abstract final class AppTheme {
  static const Color seed = Color(0xFF2196F3);

  static ThemeData light({ColorScheme? colorScheme}) =>
      _build(Brightness.light, colorScheme);

  static ThemeData dark({ColorScheme? colorScheme}) =>
      _build(Brightness.dark, colorScheme);

  /// Translates the stored preference into the mode `MaterialApp` expects.
  static ThemeMode modeOf(AppThemeMode preference) => switch (preference) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  static ThemeData _build(Brightness brightness, ColorScheme? colorScheme) {
    final scheme =
        colorScheme ??
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 3,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 3,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      cardTheme: base.cardTheme.copyWith(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
      ),
    );
  }
}
