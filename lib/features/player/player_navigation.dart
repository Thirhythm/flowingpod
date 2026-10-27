import 'package:flowingpod/features/player/player_page.dart';
import 'package:flowingpod/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the full screen player when the "点击曲目后自动打开播放器" preference is
/// enabled.
///
/// Call it after the track has been handed to the player. Nothing happens when
/// the requesting widget was disposed in the meantime, so it is safe to use
/// across an async gap.
Future<void> openPlayerIfEnabled(BuildContext context, WidgetRef ref) async {
  if (!context.mounted) return;
  if (!ref.read(autoOpenPlayerProvider)) return;
  await Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const PlayerPage()));
}
