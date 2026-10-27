import 'dart:convert';

import 'package:flowingpod/core/models/app_theme_mode.dart';
import 'package:flowingpod/core/models/audio_effect_settings.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App preferences that are not tied to a Bilibili session.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const String _autoOpenPlayerKey = 'settings_auto_open_player_v1';
  static const String _themeModeKey = 'settings_theme_mode_v1';
  static const String _dynamicColorKey = 'settings_dynamic_color_v1';
  static const String _audioEffectsKey = 'settings_audio_effects_v1';

  final SharedPreferences _prefs;

  /// Whether tapping a track should open the full screen player right away.
  bool loadAutoOpenPlayer() => _prefs.getBool(_autoOpenPlayerKey) ?? false;

  Future<void> setAutoOpenPlayer(bool value) =>
      _prefs.setBool(_autoOpenPlayerKey, value);

  /// Brightness the app should use; follows the system until changed.
  AppThemeMode loadThemeMode() =>
      AppThemeMode.fromStorage(_prefs.getString(_themeModeKey));

  Future<void> setThemeMode(AppThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  /// Whether the theme should follow the system wallpaper/accent colour.
  bool loadDynamicColor() => _prefs.getBool(_dynamicColorKey) ?? false;

  Future<void> setDynamicColor(bool value) =>
      _prefs.setBool(_dynamicColorKey, value);

  /// Equalizer and loudness enhancer preferences.
  AudioEffectSettings loadAudioEffects() {
    final raw = _prefs.getString(_audioEffectsKey);
    if (raw == null || raw.isEmpty) return const AudioEffectSettings();
    try {
      return AudioEffectSettings.fromJson(JsonUtils.map(jsonDecode(raw)));
    } on FormatException {
      return const AudioEffectSettings();
    }
  }

  Future<void> setAudioEffects(AudioEffectSettings settings) =>
      _prefs.setString(_audioEffectsKey, jsonEncode(settings.toJson()));
}
