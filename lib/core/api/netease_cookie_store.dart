import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cookie jar for the NetEase Cloud Music session.
///
/// The web API expects the cookies in a `Cookie` header, so the jar is stored
/// as a name/value map in `SharedPreferences`. Anonymous client cookies are
/// generated on first use, matching the web player's device identity.
class NeteaseCookieStore {
  NeteaseCookieStore._(this._prefs, this._cookies);

  static const String storageKey = 'netease_cookie_jar_v1';

  final SharedPreferences _prefs;
  final Map<String, String> _cookies;
  static final Random _random = Random.secure();

  /// Loads (or creates) the persisted jar synchronously, because the API
  /// client is constructed during app bootstrap.
  factory NeteaseCookieStore.fromPrefs(SharedPreferences prefs) {
    final cookies = <String, String>{};
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final name = '$key';
            final text = value == null ? '' : '$value';
            if (text.isNotEmpty && !_isAttribute(name)) cookies[name] = text;
          });
        }
      } on FormatException {
        // Corrupted jar: start fresh rather than failing at startup.
      }
    }
    final store = NeteaseCookieStore._(prefs, cookies);
    if (store._ensureClientCookies()) unawaited(store._persist());
    return store;
  }

  String? operator [](String name) => _cookies[name];

  /// `MUSIC_U` is only present once a user has logged in.
  bool get hasSession => (_cookies['MUSIC_U'] ?? '').isNotEmpty;

  /// Value for the API's `Cookie` header.
  String get header =>
      _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  /// Merges a raw `name=value; name2=value2` string (e.g. a login response).
  Future<void> mergeHeader(String? raw) async {
    if (raw == null || raw.isEmpty) return;
    var changed = false;
    for (final part in raw.split(';')) {
      final pair = part.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty || value.isEmpty || _isAttribute(name)) continue;
      _cookies[name] = value;
      changed = true;
    }
    if (changed) await _persist();
  }

  /// Parses one or more raw `Set-Cookie` header values.
  Future<void> applySetCookie(Iterable<String> setCookies) async {
    var changed = false;
    for (final raw in setCookies) {
      final pair = raw.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty || _isAttribute(name)) continue;
      if (value.isEmpty) {
        changed = _cookies.remove(name) != null || changed;
      } else {
        _cookies[name] = value;
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  static const Set<String> _attributes = {
    'path',
    'domain',
    'expires',
    'max-age',
    'httponly',
    'secure',
    'samesite',
    'version',
    'comment',
    'priority',
  };

  static bool _isAttribute(String name) =>
      _attributes.contains(name.toLowerCase());

  /// Regenerates the anonymous device cookies after a logout.
  Future<void> clear() async {
    _cookies.clear();
    _ensureClientCookies();
    await _persist();
  }

  bool _ensureClientCookies() {
    var changed = false;
    void put(String name, String value) {
      if ((_cookies[name] ?? '').isNotEmpty) return;
      _cookies[name] = value;
      changed = true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    put('_ntes_nuid', _randomHex(32));
    put('_ntes_nnid', '${_cookies['_ntes_nuid']},$now');
    put('WNMCID', '${_randomLetters(6)}.$now.01.0');
    put('os', 'pc');
    put('appver', '3.1.17.204416');
    put('osver', 'Microsoft-Windows-10-Professional-build-19045-64bit');
    put('channel', 'netease');
    put('__remember_me', 'true');
    put('ntes_kaola_ad', '1');
    put('WEVNSM', '1.0.0');
    return changed;
  }

  static String _randomHex(int bytes) => [
    for (var index = 0; index < bytes; index++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  static String _randomLetters(int count) => [
    for (var index = 0; index < count; index++)
      String.fromCharCode(0x61 + _random.nextInt(26)),
  ].join();

  Future<void> _persist() => _prefs.setString(storageKey, jsonEncode(_cookies));
}
