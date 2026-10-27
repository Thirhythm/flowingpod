import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/features/player/player_navigation.dart';
import 'package:flowingpod/state/local_history_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/track_action_menu.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Play history, sourced exclusively from this device's own play records.
class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('该操作会清空本机的播放记录，要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await ref.read(localHistoryProvider.notifier).clear();
  }

  /// Asks before deleting a single entry, then removes the track.
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
    if (!(confirmed ?? false)) return;
    await ref.read(localHistoryProvider.notifier).remove(track);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(localHistoryProvider);
    if (tracks.isEmpty) {
      return const _EmptyList(message: '还没有播放记录，去搜索一首歌吧');
    }

    return Column(
      children: [
        _HistoryToolbar(
          count: tracks.length,
          onClear: () => _confirmClear(context, ref),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return TrackTile(
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '共 $count 条',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('清空'),
        ),
      ],
    ),
  );
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 140),
      Center(child: Text(message)),
    ],
  );
}
