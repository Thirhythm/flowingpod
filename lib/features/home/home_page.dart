import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/features/library/playlist_detail_page.dart';
import 'package:flowingpod/features/player/player_navigation.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/local_history_controller.dart';
import 'package:flowingpod/state/local_recent_playlists_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/track_action_menu.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Landing page: the playlists played recently plus the six most recently
/// played tracks.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('最近播放')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(authControllerProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: const [
            _RecentPlaylists(),
            _RecentPlays(),
          ],
        ),
      ),
    );
  }
}

/// Playlists played recently, shown as large cover shortcuts at the top of
/// 最近播放. Hidden until one has been played from.
class _RecentPlaylists extends ConsumerWidget {
  const _RecentPlaylists();

  /// Home only ever surfaces a short teaser across all sources.
  static const int limit = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(localRecentPlaylistsProvider);
    if (playlists.isEmpty) return const SizedBox.shrink();
    final recent = playlists.take(limit).toList();
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: recent.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _RecentPlaylistCard(playlist: recent[index]),
      ),
    );
  }
}

class _RecentPlaylistCard extends ConsumerWidget {
  const _RecentPlaylistCard({required this.playlist});

  static const double coverWidth = 160;
  static const double coverHeight = 100;

  final RecentPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(recentPlaylistCountProvider(playlist));
    final countLabel = playlist.source == PlaylistSource.bilibili
        ? '$count 个内容'
        : '$count 首';
    return SizedBox(
      width: coverWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistDetailPage(playlist: playlist.toRef()),
          ),
        ),
        onLongPress: () => _confirmRemove(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(
              url: playlist.cover,
              width: coverWidth,
              height: coverHeight,
              radius: 12,
            ),
            const SizedBox(height: 6),
            Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              countLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks before dropping the shortcut; the playlist itself stays untouched.
  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除记录'),
        content: Text('确定将「${playlist.title}」从最近播放中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(localRecentPlaylistsProvider.notifier).remove(playlist);
    }
  }
}

class _RecentPlays extends ConsumerWidget {
  const _RecentPlays();

  /// Home only ever surfaces a short teaser; the full list lives in 媒体库.
  static const int limit = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(localHistoryProvider);
    if (history.isEmpty) {
      return const _EmptyHint('没有播放记录');
    }
    final tracks = history.take(limit).toList();
    return Column(
      children: [
        for (final track in tracks)
          TrackTile(
            track: track,
            onTap: () async {
              await ref.read(playerStateProvider.notifier).playTrack(track);
              if (!context.mounted) return;
              await openPlayerIfEnabled(context, ref);
            },
            onLongPress: () => showTrackActions(
              context,
              ref,
              track: track,
              deleteLabel: '删除',
              onDelete: () => _confirmRemove(context, ref, track),
            ),
          ),
      ],
    );
  }

  /// Asks before dropping a single entry from 最近播放.
  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    MediaTrack track,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除「${track.displayTitle}」的播放记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(localHistoryProvider.notifier).remove(track);
    }
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
