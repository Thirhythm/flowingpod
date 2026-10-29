import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cookie_vault.dart';

/// Persistent cookie jar for the Bilibili session.
///
/// The jar is stored through [CookieVault] so the session tokens live in the
/// Android keystore rather than a plain preferences file. The legacy plaintext
/// key is migrated on first launch.
class CookieStore {
  CookieStore._(this._vault, this._cookies);

  static const String _storageKey = 'bili_cookie_jar';

  final CookieVault _vault;
  final Map<String, String> _cookies;

  /// Loads (or creates) the persisted jar.
  static Future<CookieStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final vault = CookieVault.create(prefs);
    final legacy = prefs.getString(_storageKey);
    final raw = await vault.read(_storageKey);
    final cookies = <String, String>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value != null) cookies['$key'] = '$value';
          });
        }
      } on FormatException {
        // Corrupted jar: start fresh rather than crashing on launch.
      }
    }
    if (legacy != null) {
      // Move a pre-encryption jar into the keystore and drop the plaintext.
      await vault.write(_storageKey, jsonEncode(cookies));
    }
    return CookieStore._(vault, cookies);
  }

  String? operator [](String name) => _cookies[name];

  /// `SESSDATA` is only present once a user has logged in.
  bool get hasSession => (_cookies['SESSDATA'] ?? '').isNotEmpty;

  /// CSRF token required by `POST` endpoints.
  String? get csrfToken => _cookies['bili_jct'];

  /// Value for the `Cookie` request header, scoped to Bilibili hosts only.
  String headerFor(Uri uri) {
    if (!_isBilibiliHost(uri.host)) return '';
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static bool _isBilibiliHost(String host) =>
      host == 'bilibili.com' || host.endsWith('.bilibili.com');

  /// Merges [values] into the jar and persists once.
  Future<void> setAll(Map<String, String> values) async {
    if (values.isEmpty) return;
    _cookies.addAll(values);
    await _persist();
  }

  /// Parses one or more raw `Set-Cookie` header values and stores the cookies.
  Future<void> applySetCookie(Iterable<String> setCookies) async {
    var changed = false;
    for (final raw in setCookies) {
      final pair = raw.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      if (value.isEmpty) {
        changed = _cookies.remove(name) != null || changed;
      } else {
        _cookies[name] = value;
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  /// Removes every cookie (used on logout).
  Future<void> clear() async {
    _cookies.clear();
    await _vault.delete(_storageKey);
  }

  Future<void> _persist() =>
      _vault.write(_storageKey, jsonEncode(_cookies));
}
