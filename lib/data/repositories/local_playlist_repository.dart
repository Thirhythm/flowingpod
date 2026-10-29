import 'dart:async';
import 'dart:convert';

import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device playlists.
///
/// The 我喜欢的音乐 playlist is always present and cannot be deleted. Data from
/// the old flat favourites store is migrated into it on first access.
///
/// The playlist list is stored as a small index and each playlist's tracks in
/// their own key, so editing one playlist never rewrites every other playlist.
/// Reads are served from [_cache] and writes are serialised, which keeps rapid
/// edits from overwriting each other.
class LocalPlaylistRepository {
  LocalPlaylistRepository(this._prefs);

  static const String _indexKey = 'local_playlists_v3';
  static const String _legacyPlaylistsKey = 'local_playlists_v2';
  static const String _legacyFavoritesKey = 'local_favorites_v1';
  static const String _tracksPrefix = 'local_playlist_tracks_v1_';

  final SharedPreferences _prefs;

  List<LocalPlaylist>? _cache;
  Future<void> _writes = Future<void>.value();

  List<LocalPlaylist> load() {
    final cached = _cache;
    if (cached != null) return cached;

    final index = _decodeIndex(_prefs.getString(_indexKey));
    var playlists = index == null
        ? _decodeLegacyPlaylists(_prefs.getString(_legacyPlaylistsKey))
        : [
            for (final meta in index)
              LocalPlaylist(
                id: meta.id,
                name: meta.name,
                tracks: _decodeTracks(_prefs.getString(_tracksKey(meta.id))),
              ),
          ];

    final normalized = _normalize(playlists);
    final changed = !identical(normalized, playlists) || index == null;
    playlists = normalized;
    _cache = playlists;
    if (changed) unawaited(_migrate(playlists));
    return playlists;
  }

  /// Tracks of 我喜欢的音乐.
  List<MediaTrack> get likedTracks => _liked(load()).tracks;

  Future<List<LocalPlaylist>> create(String name) async {
    final trimmed = name.trim();
    final current = load();
    final next = [
      ...current,
      LocalPlaylist(
        id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
        name: trimmed.isEmpty ? '新建歌单' : trimmed,
      ),
    ];
    _cache = next;
    await _saveIndex(next);
    return next;
  }

  Future<List<LocalPlaylist>> rename(String playlistId, String name) async {
    final current = load();
    if (playlistId == LocalPlaylist.likedId) return current;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return current;
    final next = [
      for (final playlist in current)
        if (playlist.id == playlistId)
          playlist.copyWith(name: trimmed)
        else
          playlist,
    ];
    _cache = next;
    await _saveIndex(next);
    return next;
  }

  Future<List<LocalPlaylist>> remove(String playlistId) async {
    final current = load();
    if (playlistId == LocalPlaylist.likedId) return current;
    final next = [
      for (final playlist in current)
        if (playlist.id != playlistId) playlist,
    ];
    _cache = next;
    await _write(() async {
      await _prefs.setString(_indexKey, _encodeIndex(next));
      await _prefs.remove(_tracksKey(playlistId));
    });
    return next;
  }

  Future<List<LocalPlaylist>> addTracks(
    String playlistId,
    List<MediaTrack> tracks,
  ) async {
    if (tracks.isEmpty) return load();
    final current = load();
    final index = current.indexWhere((item) => item.id == playlistId);
    if (index < 0) return current;
    final merged = _merge(current[index], tracks);
    final next = [...current]..[index] = current[index].copyWith(
      tracks: merged,
    );
    _cache = next;
    await _saveTracks(playlistId, merged);
    return next;
  }

  Future<List<LocalPlaylist>> removeTracks(
    String playlistId,
    List<MediaTrack> tracks,
  ) async {
    final keys = {for (final track in tracks) track.partKey};
    if (keys.isEmpty) return load();
    final current = load();
    final index = current.indexWhere((item) => item.id == playlistId);
    if (index < 0) return current;
    final filtered = [
      for (final track in current[index].tracks)
        if (!keys.contains(track.partKey)) track,
    ];
    final next = [...current]..[index] = current[index].copyWith(
      tracks: filtered,
    );
    _cache = next;
    await _saveTracks(playlistId, filtered);
    return next;
  }

  Future<List<LocalPlaylist>> reorder(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final current = load();
    final index = current.indexWhere((item) => item.id == playlistId);
    if (index < 0) return current;
    final reordered = _reordered(current[index].tracks, oldIndex, newIndex);
    final next = [...current]..[index] = current[index].copyWith(
      tracks: reordered,
    );
    _cache = next;
    await _saveTracks(playlistId, reordered);
    return next;
  }

  Future<List<LocalPlaylist>> clearLiked() =>
      removeTracks(LocalPlaylist.likedId, likedTracks);

  List<LocalPlaylist> _normalize(List<LocalPlaylist> playlists) {
    final likedIndex = playlists.indexWhere((item) => item.isLiked);
    if (likedIndex < 0) {
      final legacyTracks = _decodeTracks(_prefs.getString(_legacyFavoritesKey));
      return [
        LocalPlaylist(
          id: LocalPlaylist.likedId,
          name: LocalPlaylist.likedName,
          tracks: legacyTracks,
        ),
        ...playlists,
      ];
    }
    final liked = playlists[likedIndex];
    final normalized = liked.name == LocalPlaylist.likedName
        ? liked
        : liked.copyWith(name: LocalPlaylist.likedName);
    if (likedIndex == 0 && identical(normalized, liked)) return playlists;
    return [
      normalized,
      for (var index = 0; index < playlists.length; index++)
        if (index != likedIndex) playlists[index],
    ];
  }

  LocalPlaylist _liked(List<LocalPlaylist> playlists) => playlists.firstWhere(
    (playlist) => playlist.isLiked,
    orElse: () => const LocalPlaylist(
      id: LocalPlaylist.likedId,
      name: LocalPlaylist.likedName,
    ),
  );

  List<MediaTrack> _merge(LocalPlaylist playlist, List<MediaTrack> incoming) {
    if (playlist.isLiked) {
      // 我喜欢的音乐 is newest first: a re-added or resolved entry moves to the
      // front instead of keeping its old slot.
      final keys = {for (final track in incoming) track.partKey};
      final seen = <String>{};
      final additions = [
        for (final track in incoming)
          if (seen.add(track.partKey)) track,
      ];
      return [
        ...additions,
        for (final track in playlist.tracks)
          if (!keys.contains(track.partKey)) track,
      ];
    }

    final tracks = [...playlist.tracks];
    final additions = <MediaTrack>[];
    final addedKeys = <String>{};
    for (final track in incoming) {
      final index = tracks.indexWhere((item) => item.partKey == track.partKey);
      if (index >= 0) {
        // Replace the stored copy with the newly seen one; a queue placeholder
        // is thereby upgraded to its resolved twin instead of being ignored.
        tracks[index] = track;
      } else if (addedKeys.add(track.partKey)) {
        additions.add(track);
      }
    }
    if (additions.isEmpty) return tracks;
    return [...tracks, ...additions];
  }

  List<MediaTrack> _reordered(
    List<MediaTrack> tracks,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= tracks.length) return tracks;
    final next = [...tracks];
    final target = newIndex.clamp(0, next.length - 1);
    if (target == oldIndex) return tracks;
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    return next;
  }

  String _tracksKey(String playlistId) => '$_tracksPrefix$playlistId';

  List<_PlaylistMeta>? _decodeIndex(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return [
        for (final item in decoded)
          if (item is Map)
            _PlaylistMeta(
              id: JsonUtils.string(item['id']),
              name: JsonUtils.string(item['name'], fallback: '未命名歌单'),
            ),
      ].where((meta) => meta.id.isNotEmpty).toList();
    } on FormatException {
      return null;
    }
  }

  List<LocalPlaylist> _decodeLegacyPlaylists(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            LocalPlaylist.fromJson(item.map((k, v) => MapEntry('$k', v))),
      ];
    } on FormatException {
      return const [];
    }
  }

  List<MediaTrack> _decodeTracks(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            MediaTrack.fromJson(item.map((k, v) => MapEntry('$k', v))),
      ];
    } on FormatException {
      return const [];
    }
  }

  String _encodeIndex(List<LocalPlaylist> playlists) => jsonEncode([
    for (final playlist in playlists)
      {'id': playlist.id, 'name': playlist.name},
  ]);

  Future<void> _migrate(List<LocalPlaylist> playlists) => _write(() async {
    for (final playlist in playlists) {
      await _prefs.setString(
        _tracksKey(playlist.id),
        jsonEncode([for (final track in playlist.tracks) track.toJson()]),
      );
    }
    await _prefs.setString(_indexKey, _encodeIndex(playlists));
    await _prefs.remove(_legacyPlaylistsKey);
    await _prefs.remove(_legacyFavoritesKey);
  });

  Future<void> _saveIndex(List<LocalPlaylist> playlists) =>
      _write(() => _prefs.setString(_indexKey, _encodeIndex(playlists)));

  Future<void> _saveTracks(String playlistId, List<MediaTrack> tracks) =>
      _write(
        () => _prefs.setString(
          _tracksKey(playlistId),
          jsonEncode([for (final track in tracks) track.toJson()]),
        ),
      );

  /// Serialises writes so an earlier save can never land after a later one.
  Future<void> _write(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }
}

class _PlaylistMeta {
  const _PlaylistMeta({required this.id, required this.name});

  final String id;
  final String name;
}
