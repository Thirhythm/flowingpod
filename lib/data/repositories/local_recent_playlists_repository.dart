import 'dart:convert';

import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device record of the playlists played from, newest first.
///
/// It feeds the home page's 最近播放 shortcuts in every session, signed in or
/// not: cloud playlists live on their service, but which ones were played is
/// app activity and has to survive logging out.
class LocalRecentPlaylistsRepository {
  LocalRecentPlaylistsRepository(this._prefs);

  static const String _key = 'local_recent_folders_v1';
  static const int _limit = 20;

  final SharedPreferences _prefs;

  List<RecentPlaylist> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            RecentPlaylist.fromJson(item.map((k, v) => MapEntry('$k', v))),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Moves [playlist] to the front and returns the updated list.
  ///
  /// Recording the same playlist again refreshes its cover and count instead of
  /// adding a second shortcut.
  Future<List<RecentPlaylist>> record(RecentPlaylist playlist) async {
    final playlists = [...load()]..remove(playlist);
    playlists.insert(0, playlist);
    if (playlists.length > _limit) {
      playlists.removeRange(_limit, playlists.length);
    }
    await _save(playlists);
    return playlists;
  }

  Future<List<RecentPlaylist>> remove(RecentPlaylist playlist) async {
    final playlists = [...load()]..remove(playlist);
    await _save(playlists);
    return playlists;
  }

  Future<void> clear() => _prefs.remove(_key);

  Future<void> _save(List<RecentPlaylist> playlists) => _prefs.setString(
    _key,
    jsonEncode([for (final playlist in playlists) playlist.toJson()]),
  );
}
