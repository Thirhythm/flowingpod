import 'package:flowingpod/core/models/app_theme_mode.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether tapping a track opens the full screen player automatically.
final NotifierProvider<AutoOpenPlayerController, bool> autoOpenPlayerProvider =
    NotifierProvider<AutoOpenPlayerController, bool>(
      AutoOpenPlayerController.new,
    );

class AutoOpenPlayerController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadAutoOpenPlayer();

  Future<void> setEnabled(bool value) async {
    await ref.read(settingsRepositoryProvider).setAutoOpenPlayer(value);
    if (ref.mounted) state = value;
  }
}

/// Brightness preference chosen in 设置, applied to the whole app.
final NotifierProvider<ThemeModeController, AppThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, AppThemeMode>(
      ThemeModeController.new,
    );

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => ref.watch(settingsRepositoryProvider).loadThemeMode();

  Future<void> setMode(AppThemeMode mode) async {
    await ref.read(settingsRepositoryProvider).setThemeMode(mode);
    if (ref.mounted) state = mode;
  }
}

/// Whether the theme follows the system wallpaper/accent colour.
final NotifierProvider<DynamicColorController, bool> dynamicColorProvider =
    NotifierProvider<DynamicColorController, bool>(DynamicColorController.new);

class DynamicColorController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadDynamicColor();

  Future<void> setEnabled(bool value) async {
    await ref.read(settingsRepositoryProvider).setDynamicColor(value);
    if (ref.mounted) state = value;
  }
}

/// Whether playback evens out the loudness of different tracks.
final NotifierProvider<VolumeLevelingController, bool> volumeLevelingProvider =
    NotifierProvider<VolumeLevelingController, bool>(
      VolumeLevelingController.new,
    );

class VolumeLevelingController extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadVolumeLeveling();

  Future<void> setEnabled(bool value) async {
    await ref.read(settingsRepositoryProvider).setVolumeLeveling(value);
    if (!ref.mounted) return;
    state = value;
    await ref.read(audioEffectsProvider).setVolumeLevelingEnabled(value);
  }
}

/// Folder downloads are saved to; `null` keeps the default Music folder.
final NotifierProvider<DownloadDirectoryController, String?>
downloadDirectoryProvider =
    NotifierProvider<DownloadDirectoryController, String?>(
      DownloadDirectoryController.new,
    );

class DownloadDirectoryController extends Notifier<String?> {
  @override
  String? build() =>
      ref.watch(settingsRepositoryProvider).loadDownloadDirectory();

  Future<void> setDirectory(String? path) async {
    await ref.read(settingsRepositoryProvider).setDownloadDirectory(path);
    if (ref.mounted) state = path;
  }
}

/// Remembered sound quality for NetEase songs, applied when a stream is
/// resolved and shown in the player's quality menu.
final NotifierProvider<NeteaseQualityController, NeteaseQuality>
neteaseQualityProvider =
    NotifierProvider<NeteaseQualityController, NeteaseQuality>(
      NeteaseQualityController.new,
    );

class NeteaseQualityController extends Notifier<NeteaseQuality> {
  @override
  NeteaseQuality build() =>
      ref.watch(settingsRepositoryProvider).loadNeteaseQuality();

  Future<void> setQuality(NeteaseQuality quality) async {
    await ref.read(settingsRepositoryProvider).setNeteaseQuality(quality);
    if (ref.mounted) state = quality;
  }
}
