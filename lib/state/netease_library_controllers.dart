import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_playlist.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playlists of the signed-in NetEase account (empty when signed out).
final AsyncNotifierProvider<NeteasePlaylistsController, List<NeteasePlaylist>>
neteasePlaylistsProvider =
    AsyncNotifierProvider<NeteasePlaylistsController, List<NeteasePlaylist>>(
      NeteasePlaylistsController.new,
    );

class NeteasePlaylistsController extends AsyncNotifier<List<NeteasePlaylist>> {
  @override
  Future<List<NeteasePlaylist>> build() async {
    final userId = ref.watch(
      neteaseAuthProvider.select((state) => state.user?.userId),
    );
    if (userId == null) return const [];
    return ref.read(neteaseRepositoryProvider).fetchUserPlaylists(userId);
  }

  Future<void> reload() async {
    final userId = ref.read(neteaseAuthProvider).user?.userId;
    if (userId == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(neteaseRepositoryProvider).fetchUserPlaylists(userId),
    );
  }
}

/// Songs of one NetEase playlist, in the order the account stores them.
final neteasePlaylistTracksProvider =
    AsyncNotifierProvider.family<
      NeteasePlaylistTracksController,
      List<MediaTrack>,
      int
    >(NeteasePlaylistTracksController.new);

class NeteasePlaylistTracksController extends AsyncNotifier<List<MediaTrack>> {
  NeteasePlaylistTracksController(this.playlistId);

  final int playlistId;

  NeteaseRepository get _repository => ref.read(neteaseRepositoryProvider);

  @override
  Future<List<MediaTrack>> build() {
    // Refetch when the account changes, so a playlist never shows the tracks
    // cached for the previous session.
    ref.watch(neteaseAuthProvider.select((state) => state.user?.userId));
    return _repository.fetchPlaylistTracks(playlistId);
  }

  /// Removes [tracks] from the playlist, updating the list optimistically.
  Future<void> removeTracks(List<MediaTrack> tracks) async {
    final current = state.value;
    if (current == null || tracks.isEmpty) return;
    final ids = {
      for (final track in tracks)
        if (track.songId > 0) track.songId,
    };
    final previous = current;
    state = AsyncData([
      for (final track in current)
        if (!ids.contains(track.songId)) track,
    ]);
    try {
      await _repository.removeTracksFromPlaylist(playlistId, ids.toList());
    } on BiliApiException {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Moves the song at [oldIndex] to [newIndex] and persists the new order.
  ///
  /// [newIndex] is the final position, as reported by `onReorderItem`.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state.value;
    if (current == null || oldIndex < 0 || oldIndex >= current.length) return;
    final next = [...current];
    final target = newIndex.clamp(0, next.length - 1);
    if (target == oldIndex) return;
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);

    final previous = current;
    state = AsyncData(next);
    try {
      await _repository.updateTrackOrder(playlistId, [
        for (final track in next) track.songId,
      ]);
    } on BiliApiException {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
