import 'package:flowingpod/core/api/netease_client.dart';
import 'package:flowingpod/core/models/app_theme_mode.dart';
import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';
import 'package:flowingpod/core/utils/storage_paths.dart';
import 'package:flowingpod/data/repositories/settings_repository.dart';
import 'package:flowingpod/data/services/audio_effects.dart';
import 'package:flowingpod/features/profile/profile_page.dart';
import 'package:flowingpod/features/settings/about_page.dart';
import 'package:flowingpod/features/settings/settings_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-out session, so the account card needs no API access.
class _SignedOutAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// Records effect requests without touching the playback engine.
class _FakeEffects implements AudioEffects {
  bool volumeLevelingEnabled = false;

  @override
  Future<EqualizerCapabilities> loadCapabilities() async =>
      EqualizerCapabilities.reference;

  @override
  Future<void> setEqualizerCurve(
    EqualizerCurve curve, {
    double preampDecibels = 0,
  }) async {}

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {}

  @override
  Future<void> setLoudnessEnabled(bool enabled) async {}

  @override
  Future<void> setLoudnessGain(double gainDecibels) async {}

  @override
  Future<void> setVolumeLevelingEnabled(bool enabled) async {
    volumeLevelingEnabled = enabled;
  }
}

/// Signed-out NetEase client, so the profile's NetEase card needs no network.
late NeteaseClient _netease;
late _FakeEffects _effects;

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _wrap(SharedPreferences prefs, Widget home) => ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    audioEffectsProvider.overrideWithValue(_effects),
    authControllerProvider.overrideWith(_SignedOutAuth.new),
    neteaseClientProvider.overrideWithValue(_netease),
  ],
  child: MaterialApp(home: home),
);

/// The brightness the settings dropdown currently shows.
AppThemeMode? _themeDropdownValue(WidgetTester tester) => tester
    .widget<DropdownButton<AppThemeMode>>(
      find.byType(DropdownButton<AppThemeMode>),
    )
    .value;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    _netease = await NeteaseClient.create(prefs);
    _effects = _FakeEffects();
  });

  test('a stored brightness falls back to the system when unknown', () {
    expect(AppThemeMode.fromStorage(null), AppThemeMode.system);
    expect(AppThemeMode.fromStorage('dark'), AppThemeMode.dark);
    expect(AppThemeMode.fromStorage('sepia'), AppThemeMode.system);
    expect(AppTheme.modeOf(AppThemeMode.light), ThemeMode.light);
    expect(AppTheme.modeOf(AppThemeMode.system), ThemeMode.system);
  });

  testWidgets('the auto open player switch defaults to off and is persisted', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    final switchTile = find.widgetWithText(SwitchListTile, '点击曲目后自动打开播放器');
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);

    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    expect(SettingsRepository(prefs).loadAutoOpenPlayer(), isTrue);

    // A fresh provider container reads the stored value back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '点击曲目后自动打开播放器'),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('动态取色 defaults to off and is persisted', (tester) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    final switchTile = find.widgetWithText(SwitchListTile, '动态取色');
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
    expect(SettingsRepository(prefs).loadDynamicColor(), isFalse);

    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    expect(SettingsRepository(prefs).loadDynamicColor(), isTrue);

    // A fresh provider container reads the stored value back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '动态取色'))
          .value,
      isTrue,
    );
  });

  testWidgets('音量均衡 defaults to off, sits above 显示模式 and is persisted', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    _effects = _FakeEffects();
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    final switchTile = find.widgetWithText(SwitchListTile, '音量均衡');
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
    expect(SettingsRepository(prefs).loadVolumeLeveling(), isFalse);
    expect(
      tester.getTopLeft(find.text('音量均衡')).dy,
      lessThan(tester.getTopLeft(find.text('显示模式')).dy),
    );

    await tester.tap(switchTile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    expect(SettingsRepository(prefs).loadVolumeLeveling(), isTrue);
    expect(_effects.volumeLevelingEnabled, isTrue);

    // A fresh provider container reads the stored value back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '音量均衡'))
          .value,
      isTrue,
    );
  });

  testWidgets('the download folder sits below 音量均衡 and is persisted', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('下载路径'), findsOneWidget);
    expect(find.text(StoragePaths.defaultMusicDirectory), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('音量均衡')).dy,
      lessThan(tester.getTopLeft(find.text('下载路径')).dy),
    );

    await SettingsRepository(prefs).setDownloadDirectory('/sdcard/Download');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('/sdcard/Download'), findsOneWidget);
  });

  testWidgets('the theme dropdown defaults to the system and is persisted', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(_themeDropdownValue(tester), AppThemeMode.system);

    await tester.tap(find.byType(DropdownButton<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppThemeMode.dark.label).last);
    await tester.pumpAndSettle();

    expect(_themeDropdownValue(tester), AppThemeMode.dark);
    expect(SettingsRepository(prefs).loadThemeMode(), AppThemeMode.dark);
    expect(AppTheme.modeOf(AppThemeMode.dark), ThemeMode.dark);

    // A fresh provider container reads the stored value back.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(prefs, const SettingsPage()));
    await tester.pumpAndSettle();

    expect(_themeDropdownValue(tester), AppThemeMode.dark);
  });

  testWidgets('我的 leads to the settings page and on to 关于', (tester) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const ProfilePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('点击曲目后自动打开播放器'), findsOneWidget);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('关于 lists the version, the developer and the repository', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    await tester.pumpWidget(_wrap(prefs, const AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('版本 ${AboutPage.appVersion}'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text(AboutPage.developerName), findsOneWidget);
    expect(find.text('开源仓库'), findsOneWidget);
    expect(find.text(AboutPage.repositoryUrl), findsOneWidget);
    // Both the developer and the repository open a browser.
    expect(find.byIcon(Icons.open_in_new_rounded), findsNWidgets(2));
  });
}
