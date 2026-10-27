import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Locally stored play history, shown while no Bilibili session is active.
final NotifierProvider<LocalHistoryController, List<MediaTrack>>
localHistoryProvider =
    NotifierProvider<LocalHistoryController, List<MediaTrack>>(
      LocalHistoryController.new,
    );

class LocalHistoryController extends Notifier<List<MediaTrack>> {
  @override
  List<MediaTrack> build() => ref.watch(localHistoryRepositoryProvider).load();

  /// Moves [track] to the front of the history.
  ///
  /// Tracks whose part id is still unknown are ignored: they are queue
  /// placeholders that the player expands into real parts, and storing them
  /// would leave a second, near identical row next to the real one.
  Future<void> record(MediaTrack track) async {
    if (!track.isResolved) return;
    final updated = await ref.read(localHistoryRepositoryProvider).record(track);
    if (ref.mounted) state = updated;
  }

  Future<void> remove(MediaTrack track) async {
    final updated = await ref
        .read(localHistoryRepositoryProvider)
        .remove(track.id);
    if (ref.mounted) state = updated;
  }

  Future<void> clear() async {
    await ref.read(localHistoryRepositoryProvider).clear();
    if (ref.mounted) state = const [];
  }
}
