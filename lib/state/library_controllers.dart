import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/history_entry.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/paged_result.dart';
import 'package:flowingpod/data/repositories/history_repository.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Favourite folders ----------------------------------------------------

final AsyncNotifierProvider<FavFoldersController, List<FavFolder>>
favFoldersProvider =
    AsyncNotifierProvider<FavFoldersController, List<FavFolder>>(
      FavFoldersController.new,
    );

/// The signed-in user's favourite folders (empty when logged out).
class FavFoldersController extends AsyncNotifier<List<FavFolder>> {
  @override
  Future<List<FavFolder>> build() async {
    final mid = ref.watch(authControllerProvider.select((s) => s.user?.mid));
    if (mid == null) return const [];
    return ref.read(favRepositoryProvider).fetchFolders(mid);
  }

  Future<void> reload() async {
    final mid = ref.read(authControllerProvider).user?.mid;
    if (mid == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(favRepositoryProvider).fetchFolders(mid),
    );
  }
}

// --- Favourite indicator --------------------------------------------------

/// Whether [track] is stored in the built-in 我喜欢的音乐 playlist.
///
/// Favouriting always writes to that local playlist, so it is the single
/// source of truth for the favourite indicator regardless of the source or
/// whether an account is signed in.
final trackFavouredProvider = Provider.family<bool, MediaTrack>((ref, track) {
  return ref.watch(
    likedTracksProvider.select(
      (tracks) => tracks.any((item) => item.partKey == track.partKey),
    ),
  );
}, isAutoDispose: true);

// --- Contents of one folder ----------------------------------------------

final favMediaProvider =
    AsyncNotifierProvider.family<
      FavMediaController,
      PagedResult<MediaTrack>,
      int
    >(FavMediaController.new);

/// Paginated contents of a single favourite folder.
class FavMediaController extends AsyncNotifier<PagedResult<MediaTrack>> {
  FavMediaController(this.mediaId);

  final int mediaId;

  bool _loadingMore = false;

  @override
  Future<PagedResult<MediaTrack>> build() =>
      ref.read(favRepositoryProvider).fetchFolderMedia(mediaId: mediaId);

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(favRepositoryProvider)
          .fetchFolderMedia(mediaId: mediaId, page: current.page + 1);
      if (!ref.mounted) return;
      state = AsyncData(
        next.copyWith(items: [...current.items, ...next.items]),
      );
    } on BiliApiException {
      // Keep the pages that already loaded; the scroll listener retries when
      // the user reaches the end again.
      if (ref.mounted) state = AsyncData(current);
    } finally {
      _loadingMore = false;
    }
  }
}

// --- Watch history -------------------------------------------------------

class HistoryState {
  const HistoryState({
    this.entries = const [],
    this.cursor = const HistoryCursor(),
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<HistoryEntry> entries;
  final HistoryCursor cursor;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String? error;

  HistoryState copyWith({
    List<HistoryEntry>? entries,
    HistoryCursor? cursor,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? error,
  }) => HistoryState(
    entries: entries ?? this.entries,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
  );
}

final NotifierProvider<HistoryController, HistoryState> historyProvider =
    NotifierProvider<HistoryController, HistoryState>(HistoryController.new);

/// Bilibili watch history of the signed-in account.
class HistoryController extends Notifier<HistoryState> {
  bool _loadingMore = false;

  @override
  HistoryState build() {
    final mid = ref.watch(authControllerProvider.select((s) => s.user?.mid));
    // Nothing is fetched while signed out; the local history is shown instead.
    if (mid != null) Future.microtask(refresh);
    return HistoryState(loading: mid != null);
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final page = await ref.read(historyRepositoryProvider).fetchHistory();
      if (!ref.mounted) return;
      state = HistoryState(
        entries: page.entries,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } on BiliApiException catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: error.message);
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !state.hasMore) return;
    _loadingMore = true;
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final page = await ref
          .read(historyRepositoryProvider)
          .fetchHistory(cursor: state.cursor);
      if (!ref.mounted) return;
      state = state.copyWith(
        entries: [...state.entries, ...page.entries],
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on BiliApiException catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loadingMore: false, error: error.message);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> remove(HistoryEntry entry) async {
    try {
      await ref.read(historyRepositoryProvider).deleteEntry(entry);
      if (!ref.mounted) return;
      state = state.copyWith(
        entries: [
          for (final item in state.entries)
            if (item.track.id != entry.track.id) item,
        ],
      );
    } on BiliApiException catch (error) {
      if (ref.mounted) state = state.copyWith(error: error.message);
    }
  }

  Future<void> clear() async {
    try {
      await ref.read(historyRepositoryProvider).clearHistory();
      if (!ref.mounted) return;
      state = const HistoryState();
    } on BiliApiException catch (error) {
      if (ref.mounted) state = state.copyWith(error: error.message);
    }
  }
}
