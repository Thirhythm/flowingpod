import 'package:flowingpod/features/player/player_page.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/marquee_text.dart';
import 'package:flowingpod/widgets/playlist_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact player that stays above the navigation bar on every page.
///
/// It renders nothing while the queue is empty, and it lives inside the page
/// body (not on top of it) so page content is never covered.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(
      playerStateProvider.select((state) => state.hasTrack),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: hasTrack
          ? const _MiniPlayerBody()
          : const SizedBox(width: double.infinity),
    );
  }
}

class _MiniPlayerBody extends ConsumerWidget {
  const _MiniPlayerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerStateProvider.select((state) => state.currentTrack),
    );
    if (track == null) return const SizedBox.shrink();

    final playing = ref.watch(playerStateProvider.select((state) => state.playing));
    final buffering = ref.watch(
      playerStateProvider.select((state) => state.buffering),
    );
    final controller = ref.read(playerStateProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlayerPage()),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MiniProgressBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  CoverImage(url: track.cover, size: 44, radius: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarqueeText(
                          text: track.displayTitle,
                          style: Theme.of(context).textTheme.titleSmall,
                          velocity: 30,
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _MiniControl(
                    icon: Icons.skip_previous_rounded,
                    tooltip: '上一曲',
                    onPressed: controller.previous,
                  ),
                  IconButton(
                    tooltip: playing ? '暂停' : '播放',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    onPressed: controller.togglePlay,
                    icon: buffering
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            size: 36,
                            color: scheme.primary,
                          ),
                  ),
                  _MiniControl(
                    icon: Icons.skip_next_rounded,
                    tooltip: '下一曲',
                    onPressed: controller.next,
                  ),
                  _MiniControl(
                    icon: Icons.queue_music_rounded,
                    tooltip: '播放列表',
                    onPressed: () => PlaylistSheet.show(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniControl extends StatelessWidget {
  const _MiniControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: 22,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

/// Isolated so the frequent position updates only rebuild this thin bar.
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position =
        ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playerStateProvider.select((state) => state.duration));
    final total = duration.inMilliseconds;
    final value = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
