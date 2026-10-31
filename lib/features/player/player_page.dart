import 'dart:math' as math;

import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/data/services/download_service.dart';
import 'package:flowingpod/features/settings/effects_page.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/state/settings_controller.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/favorite_sheet.dart';
import 'package:flowingpod/widgets/marquee_text.dart';
import 'package:flowingpod/widgets/netease_quality_sheet.dart';
import 'package:flowingpod/widgets/play_mode_button.dart';
import 'package:flowingpod/widgets/playlist_sheet.dart';
import 'package:flowingpod/widgets/storage_permission_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full screen player: artwork, metadata and playback controls.
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerStateProvider);
    final track = state.currentTrack;
    final controller = ref.read(playerStateProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('正在播放')),
      body: track == null
          ? const Center(child: Text('播放列表为空'))
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artSize = math.min(
                    constraints.maxWidth - 64,
                    constraints.maxHeight * 0.42,
                  );
                  return Column(
                    children: [
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.shadow
                                  .withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: CoverImage(
                          url: track.cover,
                          size: math.max(160, artSize),
                          radius: 16,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Full width so the names can align to the left edge.
                      SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MarqueeText(
                                text: track.displayTitle,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              MarqueeText(
                                text: track.artist,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (state.error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                          child: Text(
                            state.error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      _PlayerActionBar(track: track),
                      _SeekBar(duration: state.duration),
                      const SizedBox(height: 8),
                      _Controls(
                        playing: state.playing,
                        buffering: state.buffering,
                        onToggle: controller.togglePlay,
                        onPrevious: controller.previous,
                        onNext: controller.next,
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Secondary actions shown right above the progress bar: the equalizer, the
/// favourite toggle, the download action and, for NetEase songs, the
/// sound-quality picker.
class _PlayerActionBar extends ConsumerStatefulWidget {
  const _PlayerActionBar({required this.track});

  final MediaTrack track;

  @override
  ConsumerState<_PlayerActionBar> createState() => _PlayerActionBarState();
}

class _PlayerActionBarState extends ConsumerState<_PlayerActionBar> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    final track = widget.track;

    if (!await ensureStoragePermission(context)) return;
    if (!mounted) return;

    NeteaseQuality? quality;
    if (track.isNetease) {
      quality = await NeteaseQualitySheet.showForDownload(
        context,
        track: track,
      );
      if (quality == null || !mounted) return;
    }

    setState(() => _downloading = true);

    String message;
    try {
      final result = await ref
          .read(downloadServiceProvider)
          .enqueue(
            track,
            quality: quality,
            directory: ref.read(downloadDirectoryProvider),
          );
      message = '已开始下载（${result.qualityLabel}），进度可在通知栏查看';
    } on DownloadException catch (error) {
      message = error.message;
    } catch (_) {
      message = '下载失败，请稍后重试';
    }

    if (!mounted) return;
    setState(() => _downloading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final favoured = ref.watch(trackFavouredProvider(track));
    final quality = ref.watch(neteaseQualityProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        // NetEase songs split the actions, Bilibili entries keep the lone
        // group next to the edge.
        mainAxisAlignment: track.isNetease
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.isNetease)
                TextButton.icon(
                  onPressed: () =>
                      NeteaseQualitySheet.show(context, track: track),
                  icon: const Icon(Icons.high_quality_rounded, size: 20),
                  label: Text(quality.label),
                ),
              IconButton(
                tooltip: '下载',
                onPressed: _downloading ? null : _download,
                icon: _downloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '均衡器',
                icon: const Icon(Icons.equalizer_rounded),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EffectsPage()),
                ),
              ),
              if (track.canFavorite)
                IconButton(
                  tooltip: favoured ? '已收藏' : '收藏',
                  icon: Icon(
                    favoured
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: favoured
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: () =>
                      FavoriteSheet.show(context, ref, track: track),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.buffering,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
  });

  final bool playing;
  final bool buffering;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const PlayModeButton(iconSize: 26),
        IconButton(
          tooltip: '上一曲',
          iconSize: 40,
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox(
          width: 72,
          height: 72,
          child: IconButton.filled(
            tooltip: playing ? '暂停' : '播放',
            iconSize: 40,
            onPressed: onToggle,
            icon: buffering && !playing
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: scheme.onPrimary,
                  ),
          ),
        ),
        IconButton(
          tooltip: '下一曲',
          iconSize: 40,
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: '播放列表',
          iconSize: 26,
          onPressed: () => PlaylistSheet.show(context),
          icon: const Icon(Icons.queue_music_rounded),
        ),
      ],
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar({required this.duration});

  final Duration duration;

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragSeconds;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final total = widget.duration.inSeconds.toDouble();
    final live = position.inSeconds
        .toDouble()
        .clamp(0.0, math.max(total, 0.0))
        .toDouble();
    final current = (_dragSeconds ?? live)
        .clamp(0.0, math.max(total, 0.0))
        .toDouble();
    final label = Duration(seconds: current.round());

    return Column(
      children: [
        Slider(
          value: total > 0 ? current : 0,
          max: total > 0 ? total : 1,
          onChanged: total > 0
              ? (value) => setState(() => _dragSeconds = value)
              : null,
          onChangeEnd: (value) async {
            await ref
                .read(playerStateProvider.notifier)
                .seek(Duration(seconds: value.round()));
            if (mounted) setState(() => _dragSeconds = null);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Formatters.duration(label)),
              Text(Formatters.duration(widget.duration)),
            ],
          ),
        ),
      ],
    );
  }
}
