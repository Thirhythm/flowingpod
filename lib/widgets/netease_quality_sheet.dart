import 'dart:async';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet listing the sound qualities available for a NetEase song.
///
/// The list is discovered from the API, so a song without 无损 simply does not
/// offer it. The level actually playing is ticked; when the remembered quality
/// is missing the API falls back to 极高, which is what the tick then sits on.
class NeteaseQualitySheet extends ConsumerStatefulWidget {
  const NeteaseQualitySheet({super.key, required this.track});

  final MediaTrack track;

  static Future<void> show(BuildContext context, {required MediaTrack track}) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => NeteaseQualitySheet(track: track),
      );

  @override
  ConsumerState<NeteaseQualitySheet> createState() =>
      _NeteaseQualitySheetState();
}

class _NeteaseQualitySheetState extends ConsumerState<NeteaseQualitySheet> {
  late final Future<List<NeteaseQuality>> _qualities = ref
      .read(neteaseRepositoryProvider)
      .fetchAvailableQualities(widget.track.songId);

  /// Quality that will actually be served, mirroring the player's fallback.
  NeteaseQuality _effective(List<NeteaseQuality> available) {
    final preferred = ref.read(neteaseQualityProvider);
    if (available.contains(preferred)) return preferred;
    if (available.contains(NeteaseQuality.fallback)) {
      return NeteaseQuality.fallback;
    }
    return available.isEmpty ? preferred : available.last;
  }

  Future<void> _select(NeteaseQuality quality) async {
    final previous = ref.read(neteaseQualityProvider);
    await ref.read(neteaseQualityProvider.notifier).setQuality(quality);
    if (quality != previous) {
      unawaited(ref.read(playerStateProvider.notifier).reloadForNeteaseQuality());
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              '音质',
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              widget.track.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          FutureBuilder<List<NeteaseQuality>>(
            future: _qualities,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final available = snapshot.data ?? const <NeteaseQuality>[];
              if (available.isEmpty) {
                final error = snapshot.error;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Text(
                    error is BiliApiException
                        ? error.message
                        : '无法获取该歌曲的可用音质',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final effective = _effective(available);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final quality in available)
                    ListTile(
                      title: Text(quality.label),
                      trailing: quality == effective
                          ? Icon(
                              Icons.check_rounded,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => _select(quality),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
