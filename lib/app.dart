import 'package:flowingpod/features/shell/app_shell.dart';
import 'package:flowingpod/state/settings_controller.dart';
import 'package:flowingpod/theme/app_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget of FlowingPod.
class FlowingPodApp extends ConsumerWidget {
  const FlowingPodApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(dynamicColorProvider)) return _buildApp(ref);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => _buildApp(
        ref,
        lightColorScheme: lightDynamic?.harmonized(),
        darkColorScheme: darkDynamic?.harmonized(),
      ),
    );
  }

  Widget _buildApp(
    WidgetRef ref, {
    ColorScheme? lightColorScheme,
    ColorScheme? darkColorScheme,
  }) => MaterialApp(
    title: 'FlowingPod',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(colorScheme: lightColorScheme),
    darkTheme: AppTheme.dark(colorScheme: darkColorScheme),
    themeMode: AppTheme.modeOf(ref.watch(themeModeProvider)),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const AppShell(),
  );
}
