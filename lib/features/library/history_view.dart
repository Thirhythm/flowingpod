import 'package:flowingpod/core/models/history_entry.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/features/player/player_navigation.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_history_controller.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/local_data_banner.dart';
import 'package:flowingpod/widgets/track_action_menu.dart';
import 'package:flowingpod/widgets/track_source_badge.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Play history list whose source follows the session: the Bilibili account
/// history when signed in, the on-device history otherwise.
class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      // A no-op for the local list, which has no remote pages.
      ref.read(historyProvider.notifier).loadMore();
    }
  }

  Future<void> _confirmClear({required bool cloud}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放历史'),
        content: Text(
          cloud ? '该操作会清空哔哩哔哩账号上的全部观看历史，确定继续吗？' : '该操作会清空本机的播放记录，要继续吗？',
        ),
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
    if (cloud) {
      await ref.read(historyProvider.notifier).clear();
    } else {
      await ref.read(localHistoryProvider.notifier).clear();
    }
  }

  /// Asks before deleting a single entry, then runs [onConfirm].
  Future<void> _confirmRemove({
    required String title,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除「$title」的播放记录吗？'),
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
    await onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(
      authControllerProvider.select((state) => state.isLoggedIn),
    );
    return Column(
      children: [
        if (!loggedIn) const LocalDataBanner(message: '未登录，当前显示本地播放记录'),
        Expanded(child: loggedIn ? _buildCloud() : _buildLocal()),
      ],
    );
  }

  Widget _buildCloud() {
    final history = ref.watch(historyProvider);
    final refresh = ref.read(historyProvider.notifier).refresh;

    if (history.loading && history.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: _EmptyList(message: history.error ?? '暂无观看历史'),
      );
    }

    return Column(
      children: [
        _HistoryToolbar(
          count: history.entries.length,
          onClear: () => _confirmClear(cloud: true),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: history.entries.length + (history.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= history.entries.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: history.loadingMore
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('上拉加载更多'),
                    ),
                  );
                }
                final entry = history.entries[index];
                return _CloudHistoryTile(
                  entry: entry,
                  onTap: () async {
                    await ref
                        .read(playerStateProvider.notifier)
                        .playTrack(entry.track);
                    if (!context.mounted) return;
                    await openPlayerIfEnabled(context, ref);
                  },
                  onLongPress: () => showTrackActions(
                    context,
                    ref,
                    track: entry.track,
                    deleteLabel: '删除',
                    onDelete: () => _confirmRemove(
                      title: entry.track.displayTitle,
                      onConfirm: () =>
                          ref.read(historyProvider.notifier).remove(entry),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocal() {
    final tracks = ref.watch(localHistoryProvider);

    if (tracks.isEmpty) {
      return const _EmptyList(message: '还没有播放记录，去搜索一首歌吧');
    }

    return Column(
      children: [
        _HistoryToolbar(
          count: tracks.length,
          onClear: () => _confirmClear(cloud: false),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
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
                  onDelete: () => _confirmRemove(
                    title: track.displayTitle,
                    onConfirm: () =>
                        ref.read(localHistoryProvider.notifier).remove(track),
                  ),
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

class _CloudHistoryTile extends StatelessWidget {
  const _CloudHistoryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      entry.track.artist,
      Formatters.relativeTime(entry.viewedAt),
      if (entry.progress > Duration.zero)
        '看到 ${Formatters.duration(entry.progress)}',
    ];
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CoverImage(url: entry.track.cover, size: 56),
      title: Text(
        entry.track.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          TrackSourceBadge(source: entry.track.source),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
