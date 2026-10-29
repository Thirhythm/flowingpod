import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists one sensitive blob with the platform keystore.
///
/// Widget tests have no platform plugin and a few devices cannot open the
/// keystore; in those cases the value falls back to [SharedPreferences]. App
/// backups are disabled in the manifest, so the fallback never reaches a
/// system backup.
class CookieVault {
  CookieVault._(this._prefs, this._secure);

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage();

  /// `flutter test` runs without a platform channel; keep the tests on the
  /// in-memory preferences instead of waiting for a host that will never reply.
  static final bool _testMode =
      Platform.environment['FLUTTER_TEST'] == 'true';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  factory CookieVault.create(SharedPreferences prefs) =>
      CookieVault._(prefs, _defaultStorage);

  Future<String?> read(String key) async {
    if (!_testMode) {
      try {
        final value = await _secure.read(key: key);
        if (value != null && value.isNotEmpty) return value;
      } on MissingPluginException {
        // Unit tests do not register the platform channel.
      } on PlatformException {
        // Keystore unavailable; the fallback below keeps the session usable.
      }
    }
    return _prefs.getString(key);
  }

  Future<void> write(String key, String value) async {
    if (!_testMode) {
      try {
        await _secure.write(key: key, value: value);
        await _prefs.remove(key);
        return;
      } on MissingPluginException {
        // Fall through to the local store.
      } on PlatformException {
        // Fall through to the local store.
      }
    }
    await _prefs.setString(key, value);
  }

  Future<void> delete(String key) async {
    if (!_testMode) {
      try {
        await _secure.delete(key: key);
      } on MissingPluginException {
        // Ignore; remove the fallback copy below.
      } on PlatformException {
        // Ignore; remove the fallback copy below.
      }
    }
    await _prefs.remove(key);
  }
}
