import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/favorite_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entries the long-press menu can return.
enum TrackAction { playNext, favorite, unfavorite, delete }

/// Shows the long-press menu for [track] and runs the chosen action.
///
/// Every list of playable items — recent plays, search results and history —
/// shares this menu, so the actions stay identical everywhere.
///
/// Unless [showFavorite] is false, the menu carries a favourite entry that
/// reads 收藏 or 取消收藏 depending on whether the track is already stored, and
/// stores or drops it accordingly. Lists that can only remove — the favourites
/// themselves — pass `false` and offer [deleteLabel] instead. That removal
/// entry is performed by [onDelete], which also owns any confirmation.
Future<void> showTrackActions(
  BuildContext context,
  WidgetRef ref, {
  required MediaTrack track,
  bool showFavorite = true,
  String? deleteLabel,
  Future<void> Function()? onDelete,
}) async {
  assert(
    deleteLabel == null || onDelete != null,
    'a delete entry needs the callback that performs it',
  );
  final action = await showModalBottomSheet<TrackAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _TrackActionSheet(
      track: track,
      showFavorite: showFavorite,
      deleteLabel: deleteLabel,
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case TrackAction.playNext:
      final queued = await ref
          .read(playerStateProvider.notifier)
          .addToNext(track);
      if (!context.mounted) return;
      _toast(context, queued ? '已添加到下一首播放' : '该歌曲正在播放');
    case TrackAction.favorite:
      await _addFavorite(context, ref, track);
    case TrackAction.unfavorite:
      await _removeFavorite(context, ref, track);
    case TrackAction.delete:
      await onDelete?.call();
  }
}

/// Stores [track] in 我喜欢的音乐 and opens the playlist picker.
Future<void> _addFavorite(
  BuildContext context,
  WidgetRef ref,
  MediaTrack track,
) async {
  if (!track.canFavorite) return;
  await FavoriteSheet.show(context, ref, track: track);
}

/// Drops [track] from 我喜欢的音乐 and, when signed in, from the source
/// service's favourite collection.
Future<void> _removeFavorite(
  BuildContext context,
  WidgetRef ref,
  MediaTrack track,
) async {
  await ref.read(localPlaylistsProvider.notifier).removeTracks(
    LocalPlaylist.likedId,
    [track],
  );

  if (track.isNetease) {
    if (ref.read(neteaseAuthProvider).isLoggedIn && track.songId > 0) {
      try {
        await ref
            .read(neteaseRepositoryProvider)
            .likeSong(track.songId, like: false);
      } on BiliApiException {
        // The local removal above is what the indicator reflects.
      }
    }
  } else if (ref.read(authControllerProvider).isLoggedIn) {
    try {
      // One video can sit in several folders, so 取消收藏 empties them all.
      final folders = await ref.read(favFoldersProvider.future);
      if (folders.isNotEmpty) {
        await ref
            .read(favRepositoryProvider)
            .dealResources(
              aid: track.aid,
              removeFrom: [for (final folder in folders) folder.id],
            );
        ref.invalidate(favFoldersProvider);
      }
    } on BiliApiException {
      // Best-effort: the local favourite was already removed.
    }
  }
  if (context.mounted) _toast(context, '已取消收藏');
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );

class _TrackActionSheet extends ConsumerWidget {
  const _TrackActionSheet({
    required this.track,
    this.showFavorite = true,
    this.deleteLabel,
  });

  final MediaTrack track;
  final bool showFavorite;
  final String? deleteLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the lists that offer 收藏 need to know whether it is stored already.
    final favoured = showFavorite && ref.watch(trackFavouredProvider(track));
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              track.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('添加到下一首播放'),
            onTap: () => Navigator.of(context).pop(TrackAction.playNext),
          ),
          if (showFavorite)
            ListTile(
              leading: Icon(
                favoured
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(favoured ? '取消收藏' : '收藏'),
              onTap: () => Navigator.of(
                context,
              ).pop(favoured ? TrackAction.unfavorite : TrackAction.favorite),
            ),
          if (deleteLabel != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(deleteLabel!),
              onTap: () => Navigator.of(context).pop(TrackAction.delete),
            ),
        ],
      ),
    );
  }
}
