import 'dart:async';
import 'dart:convert';

import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device playlists.
///
/// The 我喜欢的音乐 playlist is always present and cannot be deleted. Data from
/// the old flat favourites store is migrated into it on first access.
class LocalPlaylistRepository {
  LocalPlaylistRepository(this._prefs);

  static const String _key = 'local_playlists_v2';
  static const String _legacyFavoritesKey = 'local_favorites_v1';

  final SharedPreferences _prefs;

  List<LocalPlaylist> load() {
    var playlists = _decode(_prefs.getString(_key));

    final likedIndex = playlists.indexWhere((item) => item.isLiked);
    if (likedIndex < 0) {
      final legacyTracks = _decodeLegacyTracks(
        _prefs.getString(_legacyFavoritesKey),
      );
      playlists = [
        LocalPlaylist(
          id: LocalPlaylist.likedId,
          name: LocalPlaylist.likedName,
          tracks: legacyTracks,
        ),
        ...playlists,
      ];
      unawaited(_save(playlists));
      if (_prefs.containsKey(_legacyFavoritesKey)) {
        unawaited(_prefs.remove(_legacyFavoritesKey));
      }
    } else {
      final liked = playlists[likedIndex];
      final normalized = liked.name == LocalPlaylist.likedName
          ? liked
          : liked.copyWith(name: LocalPlaylist.likedName);
      if (likedIndex != 0) {
        playlists = [
          normalized,
          for (var index = 0; index < playlists.length; index++)
            if (index != likedIndex) playlists[index],
        ];
      } else if (!identical(normalized, liked)) {
        playlists = [normalized, ...playlists.skip(1)];
      }
    }

    return playlists;
  }

  /// Tracks of 我喜欢的音乐.
  List<MediaTrack> get likedTracks => _liked(load()).tracks;

  Future<List<LocalPlaylist>> create(String name) async {
    final trimmed = name.trim();
    final playlists = [
      ...load(),
      LocalPlaylist(
        id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
        name: trimmed.isEmpty ? '新建歌单' : trimmed,
      ),
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> rename(String playlistId, String name) async {
    if (playlistId == LocalPlaylist.likedId) return load();
    final trimmed = name.trim();
    if (trimmed.isEmpty) return load();
    final playlists = [
      for (final playlist in load())
        if (playlist.id == playlistId)
          playlist.copyWith(name: trimmed)
        else
          playlist,
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> remove(String playlistId) async {
    if (playlistId == LocalPlaylist.likedId) return load();
    final playlists = [
      for (final playlist in load())
        if (playlist.id != playlistId) playlist,
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> addTracks(
    String playlistId,
    List<MediaTrack> tracks,
  ) async {
    if (tracks.isEmpty) return load();
    final playlists = [
      for (final playlist in load())
        if (playlist.id == playlistId)
          playlist.copyWith(tracks: _merge(playlist, tracks))
        else
          playlist,
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> removeTracks(
    String playlistId,
    List<MediaTrack> tracks,
  ) async {
    final keys = {for (final track in tracks) track.partKey};
    if (keys.isEmpty) return load();
    final playlists = [
      for (final playlist in load())
        if (playlist.id == playlistId)
          playlist.copyWith(
            tracks: [
              for (final track in playlist.tracks)
                if (!keys.contains(track.partKey)) track,
            ],
          )
        else
          playlist,
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> reorder(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final playlists = [
      for (final playlist in load())
        if (playlist.id == playlistId)
          playlist.copyWith(
            tracks: _reordered(playlist.tracks, oldIndex, newIndex),
          )
        else
          playlist,
    ];
    await _save(playlists);
    return playlists;
  }

  Future<List<LocalPlaylist>> clearLiked() =>
      removeTracks(LocalPlaylist.likedId, likedTracks);

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

  LocalPlaylist _liked(List<LocalPlaylist> playlists) => playlists.firstWhere(
    (playlist) => playlist.isLiked,
    orElse: () => const LocalPlaylist(
      id: LocalPlaylist.likedId,
      name: LocalPlaylist.likedName,
    ),
  );

  List<LocalPlaylist> _decode(String? raw) {
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

  List<MediaTrack> _decodeLegacyTracks(String? raw) {
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

  Future<void> _save(List<LocalPlaylist> playlists) => _prefs.setString(
    _key,
    jsonEncode([for (final playlist in playlists) playlist.toJson()]),
  );
}
