import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/data/repositories/local_playlist_repository.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// All playlists stored on this device, 我喜欢的音乐 first.
final NotifierProvider<LocalPlaylistsController, List<LocalPlaylist>>
localPlaylistsProvider =
    NotifierProvider<LocalPlaylistsController, List<LocalPlaylist>>(
      LocalPlaylistsController.new,
    );

/// Tracks of the built-in 我喜欢的音乐 playlist.
final Provider<List<MediaTrack>> likedTracksProvider =
    Provider<List<MediaTrack>>(
      (ref) => ref
          .watch(localPlaylistsProvider)
          .firstWhere(
            (playlist) => playlist.isLiked,
            orElse: () => const LocalPlaylist(
              id: LocalPlaylist.likedId,
              name: LocalPlaylist.likedName,
            ),
          )
          .tracks,
    );

class LocalPlaylistsController extends Notifier<List<LocalPlaylist>> {
  LocalPlaylistRepository get _repository =>
      ref.read(localPlaylistRepositoryProvider);

  @override
  List<LocalPlaylist> build() => _repository.load();

  Future<LocalPlaylist> create(String name) async {
    final updated = await _repository.create(name);
    if (ref.mounted) state = updated;
    return updated.last;
  }

  Future<void> rename(String id, String name) async {
    final updated = await _repository.rename(id, name);
    if (ref.mounted) state = updated;
  }

  Future<void> remove(String id) async {
    final updated = await _repository.remove(id);
    if (ref.mounted) state = updated;
  }

  Future<void> addTracks(String id, List<MediaTrack> tracks) async {
    final updated = await _repository.addTracks(id, tracks);
    if (ref.mounted) state = updated;
  }

  Future<void> removeTracks(String id, List<MediaTrack> tracks) async {
    final updated = await _repository.removeTracks(id, tracks);
    if (ref.mounted) state = updated;
  }

  Future<void> reorder(String id, int oldIndex, int newIndex) async {
    final updated = await _repository.reorder(id, oldIndex, newIndex);
    if (ref.mounted) state = updated;
  }
}
