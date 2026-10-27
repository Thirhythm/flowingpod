import 'package:flowingpod/core/models/recent_folder.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-device record of the favourite folders played from, feeding the home
/// page's shortcuts.
final NotifierProvider<LocalRecentFoldersController, List<RecentFolder>>
localRecentFoldersProvider =
    NotifierProvider<LocalRecentFoldersController, List<RecentFolder>>(
      LocalRecentFoldersController.new,
    );

class LocalRecentFoldersController extends Notifier<List<RecentFolder>> {
  @override
  List<RecentFolder> build() =>
      ref.watch(localRecentFoldersRepositoryProvider).load();

  /// Moves [folder] to the front of the list.
  Future<void> record(RecentFolder folder) async {
    final updated = await ref
        .read(localRecentFoldersRepositoryProvider)
        .record(folder);
    if (ref.mounted) state = updated;
  }

  Future<void> remove(RecentFolder folder) async {
    final updated = await ref
        .read(localRecentFoldersRepositoryProvider)
        .remove(folder.id);
    if (ref.mounted) state = updated;
  }

  Future<void> clear() async {
    await ref.read(localRecentFoldersRepositoryProvider).clear();
    if (ref.mounted) state = const [];
  }
}
