import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/track_source.dart';
import 'package:flowingpod/features/player/player_navigation.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/search_controller.dart';
import 'package:flowingpod/widgets/track_action_menu.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Searches both supported services and plays the selected result's audio.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _queryController = TextEditingController();
  late final TabController _tabController;
  int _lastIndex = 0;

  TrackSource get _source =>
      _tabController.index == 0 ? TrackSource.bilibili : TrackSource.netease;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  /// Switching tabs reuses the current query, so both services can be compared
  /// without retyping it.
  void _onTabChanged() {
    if (_lastIndex == _tabController.index) return;
    _lastIndex = _tabController.index;
    setState(() {});
    final term = _queryController.text.trim();
    if (term.isEmpty) return;
    final state = ref.read(searchControllerProvider(_source));
    if (state.keyword != term && !state.loading) {
      ref.read(searchControllerProvider(_source).notifier).search(term);
    }
  }

  /// The suggestion term is derived from the controller, so every keystroke
  /// must rebuild the page for the list to follow the text.
  void _onQueryChanged() => setState(() {});

  /// Runs a search on the active tab and closes the suggestion list.
  void _searchWith(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    if (_queryController.text != trimmed) {
      _queryController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider(_source).notifier).search(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final biliState = ref.watch(searchControllerProvider(TrackSource.bilibili));
    final neteaseState = ref.watch(
      searchControllerProvider(TrackSource.netease),
    );
    final activeState = _source == TrackSource.bilibili
        ? biliState
        : neteaseState;
    final term = _queryController.text.trim();
    final hasQuery = term.isNotEmpty;
    final showSuggestions = hasQuery && term != activeState.keyword;
    // The source tabs only make sense once a result area is on screen.
    final showTabs =
        !showSuggestions &&
        (biliState.keyword.isNotEmpty || neteaseState.keyword.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          textInputAction: TextInputAction.search,
          onSubmitted: _searchWith,
          decoration: const InputDecoration(
            hintText: '搜索......',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => _searchWith(_queryController.text),
          ),
          if (activeState.results.isNotEmpty || hasQuery)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _queryController.clear();
                for (final source in TrackSource.values) {
                  ref.read(searchControllerProvider(source).notifier).clear();
                }
                _lastIndex = 0;
                if (_tabController.index != 0) _tabController.index = 0;
              },
            ),
        ],
        bottom: showTabs
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '哔哩哔哩'),
                  Tab(text: '网易云音乐'),
                ],
              )
            : null,
      ),
      body: TabBarView(
        controller: _tabController,
        physics: showTabs ? null : const NeverScrollableScrollPhysics(),
        children: [
          for (final source in TrackSource.values)
            _SearchTab(source: source, term: term, onSearch: _searchWith),
        ],
      ),
    );
  }
}

/// Results of one source. Each tab keeps its own scroll position and search
/// state, so switching tabs does not lose the other service's results.
class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab({
    required this.source,
    required this.term,
    required this.onSearch,
  });

  final TrackSource source;
  final String term;
  final ValueChanged<String> onSearch;

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(searchControllerProvider(widget.source).notifier).loadMore();
    }
  }

  Future<void> _play(int index, List<MediaTrack> results) async {
    final track = results[index];
    await ref.read(playerStateProvider.notifier).playTrack(track);
    if (!mounted) return;
    await openPlayerIfEnabled(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider(widget.source));
    final showSuggestions =
        widget.term.isNotEmpty && widget.term != state.keyword;

    if (showSuggestions) {
      return _SuggestionList(term: widget.term, onSelected: widget.onSearch);
    }

    final results = state.results;
    return _SearchBody(
      state: state,
      scrollController: _scrollController,
      onRetry: () => ref
          .read(searchControllerProvider(widget.source).notifier)
          .search(state.keyword),
      onPlay: (index) => _play(index, results),
      onLongPress: (index) =>
          showTrackActions(context, ref, track: results[index]),
    );
  }
}

/// Keyword suggestions shown while the user is still typing.
///
/// Suggestions always come from NetEase Cloud Music, regardless of the active
/// result tab.
class _SuggestionList extends ConsumerWidget {
  const _SuggestionList({required this.term, required this.onSelected});

  final String term;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(searchSuggestionsProvider(term));

    return suggestions.when(
      // Stay blank rather than flashing a spinner on every keystroke.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                leading: const Icon(Icons.search_rounded, size: 20),
                title: Text(
                  items[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelected(items[index]),
              ),
            ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.state,
    required this.scrollController,
    required this.onRetry,
    required this.onPlay,
    required this.onLongPress,
  });

  final SearchState state;
  final ScrollController scrollController;
  final VoidCallback onRetry;
  final void Function(int index) onPlay;
  final void Function(int index) onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline_rounded,
        message: state.error!,
        action: TextButton(onPressed: onRetry, child: const Text('重试')),
      );
    }
    if (state.keyword.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.search_rounded,
        message: '输入关键词搜索',
      );
    }
    if (state.isEmptyResult) {
      return const _CenteredMessage(
        icon: Icons.sentiment_dissatisfied_rounded,
        message: '没有找到相关内容，换个关键词试试',
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: state.results.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: state.loadingMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text('上拉加载更多', style: theme.textTheme.bodySmall),
            ),
          );
        }
        return TrackTile(
          track: state.results[index],
          showSource: false,
          onTap: () => onPlay(index),
          onLongPress: () => onLongPress(index),
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  /// Centred while there is room, scrollable once the on-screen keyboard leaves
  /// less space than the content needs, so the page can never overflow.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
