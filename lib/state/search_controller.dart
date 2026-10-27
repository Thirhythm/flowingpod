import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchState {
  const SearchState({
    required this.source,
    this.keyword = '',
    this.results = const [],
    this.page = 1,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final TrackSource source;
  final String keyword;
  final List<MediaTrack> results;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String? error;

  bool get isEmptyResult =>
      !loading && results.isEmpty && error == null && keyword.isNotEmpty;
}

final searchControllerProvider =
    NotifierProvider.family<SearchController, SearchState, TrackSource>(
      SearchController.new,
    );

/// Search suggestions, always supplied by NetEase Cloud Music.
///
/// The lookup is debounced by disposing the provider as soon as the term
/// changes, so an abandoned keystroke never reaches the network.
final searchSuggestionsProvider = FutureProvider.family<List<String>, String>((
  ref,
  term,
) async {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return const [];

  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!ref.mounted) return const [];

  return ref.read(neteaseRepositoryProvider).suggest(trimmed);
}, isAutoDispose: true);

/// Keyword search with pagination, kept separate per source so the two tabs
/// can show their own results.
class SearchController extends Notifier<SearchState> {
  SearchController(this.source);

  final TrackSource source;

  bool _loadingMore = false;

  @override
  SearchState build() => SearchState(source: source);

  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      state = SearchState(source: source);
      return;
    }
    state = SearchState(source: source, keyword: trimmed, loading: true);
    try {
      final result = switch (source) {
        TrackSource.bilibili =>
          await ref
              .read(searchRepositoryProvider)
              .searchVideos(keyword: trimmed),
        TrackSource.netease =>
          await ref
              .read(neteaseRepositoryProvider)
              .searchSongs(keyword: trimmed),
      };
      if (!ref.mounted) return;
      state = SearchState(
        source: source,
        keyword: trimmed,
        results: result.items,
        page: result.page,
        hasMore: result.hasMore,
      );
    } on BiliApiException catch (error) {
      if (!ref.mounted) return;
      state = SearchState(
        source: source,
        keyword: trimmed,
        error: error.message,
      );
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !state.hasMore || state.loading) return;
    _loadingMore = true;
    state = SearchState(
      source: source,
      keyword: state.keyword,
      results: state.results,
      page: state.page,
      hasMore: state.hasMore,
      loadingMore: true,
    );
    try {
      final result = switch (source) {
        TrackSource.bilibili =>
          await ref
              .read(searchRepositoryProvider)
              .searchVideos(keyword: state.keyword, page: state.page + 1),
        TrackSource.netease =>
          await ref
              .read(neteaseRepositoryProvider)
              .searchSongs(keyword: state.keyword, page: state.page + 1),
      };
      if (!ref.mounted) return;
      state = SearchState(
        source: source,
        keyword: state.keyword,
        results: [...state.results, ...result.items],
        page: result.page,
        hasMore: result.hasMore,
      );
    } on BiliApiException catch (error) {
      if (!ref.mounted) return;
      state = SearchState(
        source: source,
        keyword: state.keyword,
        results: state.results,
        page: state.page,
        hasMore: state.hasMore,
        error: error.message,
      );
    } finally {
      _loadingMore = false;
    }
  }

  void clear() => state = SearchState(source: source);
}
