import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/netease_library_controllers.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-device record of the playlists played from, feeding the home page's
/// shortcuts.
final NotifierProvider<LocalRecentPlaylistsController, List<RecentPlaylist>>
localRecentPlaylistsProvider =
    NotifierProvider<LocalRecentPlaylistsController, List<RecentPlaylist>>(
      LocalRecentPlaylistsController.new,
    );

/// Current track count of a recently played playlist.
///
/// The count stored with a shortcut is only the snapshot taken when it was
/// played; the playlist may have gained or lost entries since. The playlist's
/// own source is consulted for the up-to-date count, falling back to that
/// snapshot when the source is unavailable (signed out, still loading, or the
/// playlist no longer exists).
final recentPlaylistCountProvider = Provider.family<int, RecentPlaylist>(
  (ref, playlist) {
    switch (playlist.source) {
      case PlaylistSource.local:
        for (final item in ref.watch(localPlaylistsProvider)) {
          if (item.id == playlist.id) return item.tracks.length;
        }
      case PlaylistSource.bilibili:
        final folders = ref.watch(favFoldersProvider).value;
        if (folders != null) {
          for (final folder in folders) {
            if ('${folder.id}' == playlist.id) return folder.mediaCount;
          }
        }
      case PlaylistSource.netease:
        final playlists = ref.watch(neteasePlaylistsProvider).value;
        if (playlists != null) {
          for (final item in playlists) {
            if ('${item.id}' == playlist.id) return item.trackCount;
          }
        }
    }
    return playlist.count;
  },
);

class LocalRecentPlaylistsController extends Notifier<List<RecentPlaylist>> {
  @override
  List<RecentPlaylist> build() =>
      ref.watch(localRecentPlaylistsRepositoryProvider).load();

  /// Moves [playlist] to the front of the list.
  Future<void> record(RecentPlaylist playlist) async {
    final updated = await ref
        .read(localRecentPlaylistsRepositoryProvider)
        .record(playlist);
    if (ref.mounted) state = updated;
  }

  Future<void> remove(RecentPlaylist playlist) async {
    final updated = await ref
        .read(localRecentPlaylistsRepositoryProvider)
        .remove(playlist);
    if (ref.mounted) state = updated;
  }

  Future<void> clear() async {
    await ref.read(localRecentPlaylistsRepositoryProvider).clear();
    if (ref.mounted) state = const [];
  }
}
