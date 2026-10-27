import 'dart:convert';

import 'package:flowingpod/core/models/media_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device play history of everything played in this app.
///
/// It feeds the home page's "最近播放" in every session, signed in or not, and
/// backs the library's local history while no Bilibili session is available.
///
/// Only resolved tracks are stored: entries whose part id (`cid`) is still
/// unknown are queue placeholders, and keeping them would show the same song
/// twice once the player expands them into their real parts.
class LocalHistoryRepository {
  LocalHistoryRepository(this._prefs);

  static const String _key = 'local_history_v1';
  static const int _limit = 100;

  final SharedPreferences _prefs;

  List<MediaTrack> load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            if (MediaTrack.fromJson(item.map((k, v) => MapEntry('$k', v)))
                case final track when track.isResolved)
              track,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Moves [track] to the front and returns the updated list.
  ///
  /// Placeholders whose part id is unknown are rejected, so a played song can
  /// never end up stored twice.
  Future<List<MediaTrack>> record(MediaTrack track) async {
    if (!track.isResolved) return load();
    final tracks = [...load()]..removeWhere((item) => item.id == track.id);
    tracks.insert(0, track);
    if (tracks.length > _limit) {
      tracks.removeRange(_limit, tracks.length);
    }
    await _save(tracks);
    return tracks;
  }

  Future<List<MediaTrack>> remove(String trackId) async {
    final tracks = [...load()]..removeWhere((item) => item.id == trackId);
    await _save(tracks);
    return tracks;
  }

  Future<void> clear() => _prefs.remove(_key);

  Future<void> _save(List<MediaTrack> tracks) => _prefs.setString(
    _key,
    jsonEncode([for (final track in tracks) track.toJson()]),
  );
}
