import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-device record of the playlists played from, feeding the home page's
/// shortcuts.
final NotifierProvider<LocalRecentPlaylistsController, List<RecentPlaylist>>
localRecentPlaylistsProvider =
    NotifierProvider<LocalRecentPlaylistsController, List<RecentPlaylist>>(
      LocalRecentPlaylistsController.new,
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
