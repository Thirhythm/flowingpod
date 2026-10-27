import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cycles through the playback orders and briefly explains the new one.
class PlayModeButton extends ConsumerWidget {
  const PlayModeButton({super.key, this.iconSize = 24});

  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playerStateProvider.select((state) => state.mode));
    return IconButton(
      tooltip: mode.label,
      iconSize: iconSize,
      icon: Icon(_iconFor(mode)),
      onPressed: () {
        ref.read(playerStateProvider.notifier).cycleMode();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger
          ?..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(mode.next.label),
              duration: const Duration(milliseconds: 1200),
            ),
          );
      },
    );
  }

  static IconData _iconFor(PlayMode mode) => switch (mode) {
    PlayMode.sequential => Icons.playlist_play_rounded,
    PlayMode.listLoop => Icons.repeat_rounded,
    PlayMode.singleLoop => Icons.repeat_one_rounded,
    PlayMode.shuffle => Icons.shuffle_rounded,
  };
}
