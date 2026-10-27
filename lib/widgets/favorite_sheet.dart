import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/widgets/playlist_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Favouriting stores the track in 我喜欢的音乐 and then lets the user pick
/// additional playlists of the same service.
abstract final class FavoriteSheet {
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required MediaTrack track,
  }) async {
    await ref.read(localPlaylistsProvider.notifier).addTracks(
      LocalPlaylist.likedId,
      [track],
    );
    if (!context.mounted) return;

    final initial = {
      for (final playlist in ref.read(localPlaylistsProvider))
        if (playlist.tracks.any((item) => item.partKey == track.partKey))
          PlaylistSelection(PlaylistSource.local, playlist.id),
    };
    final selected = await showPlaylistPickerSheet(
      context,
      ref,
      tracks: [track],
      origin: _originOf(track.source),
      initialSelection: initial,
      title: '收藏到歌单',
      subtitle: '已加入「${LocalPlaylist.likedName}」',
    );
    if (selected == null || !context.mounted) return;

    final error = await applyPlaylistSelections(
      ref,
      [track],
      selected,
      initial: initial,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '已更新收藏'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static PlaylistSource _originOf(TrackSource source) =>
      source == TrackSource.netease
      ? PlaylistSource.netease
      : PlaylistSource.bilibili;
}
