import 'dart:math' as math;

import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/play_mode_button.dart';
import 'package:flowingpod/widgets/track_source_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet listing the current queue.
class PlaylistSheet extends ConsumerStatefulWidget {
  const PlaylistSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const PlaylistSheet(),
  );

  @override
  ConsumerState<PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<PlaylistSheet> {
  /// Every row is the same dense tile, so one height describes them all. It
  /// only seeds the opening offset; the final position is taken from the row
  /// once it is laid out.
  static const double _estimatedRowHeight = 68;

  final GlobalKey _currentRowKey = GlobalKey();

  late final ScrollController _controller;

  /// The opening position is applied once: later rebuilds (the track changing,
  /// an entry being removed) must not drag the viewport away from the user.
  bool _aligned = false;

  @override
  void initState() {
    super.initState();
    // Seeded so the current row is laid out in the first frame and can then be
    // measured.
    final index = ref.read(playerStateProvider).currentIndex;
    _controller = ScrollController(
      initialScrollOffset: math.max(0, (index - 1) * _estimatedRowHeight),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scrolls the current row to the second position, so the track that is
  /// playing sits in context rather than pinned to the very top.
  ///
  /// [Scrollable.ensureVisible] clamps to the scrollable range, so a queue that
  /// already fits — or a current row with nothing above it — stays where it is.
  void _alignToCurrentRow() {
    if (!_controller.hasClients) return;
    final rowContext = _currentRowKey.currentContext;
    if (rowContext == null) return;
    final rowHeight = (rowContext.findRenderObject()! as RenderBox).size.height;
    final slack = _controller.position.viewportDimension - rowHeight;
    final alignment = slack <= 0 ? 0.0 : (rowHeight / slack).clamp(0.0, 1.0);
    Scrollable.ensureVisible(rowContext, alignment: alignment);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerStateProvider);
    final controller = ref.read(playerStateProvider.notifier);
    final theme = Theme.of(context);

    if (!_aligned && state.queue.isNotEmpty) {
      _aligned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _alignToCurrentRow();
      });
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '播放列表（${state.queue.length}）',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const PlayModeButton(iconSize: 22),
                IconButton(
                  tooltip: '清空播放列表',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: state.queue.isEmpty
                      ? null
                      : () async {
                          final confirmed = await _confirmClear(context);
                          if (confirmed) await controller.clear();
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.queue.isEmpty
                ? Center(
                    child: Text(
                      '播放列表为空',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _controller,
                    itemCount: state.queue.length,
                    itemBuilder: (context, index) {
                      final isCurrent = index == state.currentIndex;
                      return _QueueRow(
                        track: state.queue[index],
                        isCurrent: isCurrent,
                        rowKey: isCurrent ? _currentRowKey : null,
                        onTap: () {
                          controller.playAt(index);
                          Navigator.of(context).maybePop();
                        },
                        onRemove: () => controller.removeAt(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空播放列表'),
        content: const Text('将停止播放并清空当前播放列表，确定继续吗？'),
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
    return result ?? false;
  }
}

/// One entry of the queue.
///
/// The row brings its own [Material] because a tile paints its background on
/// the nearest material ancestor. Without it the selected colour would be
/// painted by the sheet itself, which the list viewport does not clip, and
/// would bleed over the sheet header whenever the row is only partly scrolled
/// into view.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.isCurrent,
    required this.rowKey,
    required this.onTap,
    required this.onRemove,
  });

  final MediaTrack track;
  final bool isCurrent;
  final Key? rowKey;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: rowKey,
        dense: true,
        selected: isCurrent,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.35,
        ),
        leading: CoverImage(url: track.cover, size: 40, radius: 6),
        title: Text(
          track.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent ? theme.colorScheme.primary : null,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Row(
          children: [
            TrackSourceBadge(source: track.source),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: '从列表移除',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: onRemove,
        ),
        onTap: onTap,
      ),
    );
  }
}
