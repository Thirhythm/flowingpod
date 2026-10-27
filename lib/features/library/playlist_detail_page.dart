import 'dart:async';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/core/models/recent_playlist.dart';
import 'package:flowingpod/features/player/player_navigation.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/local_recent_playlists_controller.dart';
import 'package:flowingpod/state/netease_library_controllers.dart';
import 'package:flowingpod/state/player_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/player_scaffold.dart';
import 'package:flowingpod/widgets/playlist_picker_sheet.dart';
import 'package:flowingpod/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Data the current playlist exposes, normalised across the three sources.
class _PlaylistData {
  const _PlaylistData({
    required this.tracks,
    this.loading = false,
    this.error,
    this.hasMore = false,
    this.canReorder = false,
    this.removeTracks,
  });

  final List<MediaTrack> tracks;
  final bool loading;
  final String? error;
  final bool hasMore;
  final bool canReorder;
  final Future<void> Function(List<MediaTrack> tracks)? removeTracks;
}

/// Contents of a local, Bilibili or NetEase playlist.
///
/// Long pressing a row enters the batch mode: items can be selected, removed
/// and copied into another playlist. Local and NetEase playlists can also be
/// reordered there, by dragging the handle shown on each row.
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final PlaylistRef playlist;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _busy = false;

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
    if (widget.playlist.source != PlaylistSource.bilibili) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(favMediaProvider(widget.playlist.numericId).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data();
    final selectedTracks = [
      for (final track in data.tracks)
        if (_selected.contains(track.id)) track,
    ];

    return PlayerScaffold(
      title: Text(
        _selecting ? '已选择 ${_selected.length} 项' : widget.playlist.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: _actions(data, selectedTracks),
      body: _body(data, selectedTracks),
    );
  }

  List<Widget> _actions(_PlaylistData data, List<MediaTrack> selectedTracks) {
    if (_selecting) {
      final allSelected =
          data.tracks.isNotEmpty && _selected.length == data.tracks.length;
      return [
        IconButton(
          tooltip: '退出批量操作',
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelection,
        ),
        IconButton(
          tooltip: allSelected ? '取消全选' : '全选',
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
          ),
          onPressed: data.tracks.isEmpty
              ? null
              : () => setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected.addAll([for (final t in data.tracks) t.id]);
                  }
                }),
        ),
        IconButton(
          tooltip: '添加到歌单',
          icon: const Icon(Icons.playlist_add_rounded),
          onPressed: selectedTracks.isEmpty || _busy
              ? null
              : () => _addSelected(selectedTracks),
        ),
        IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: selectedTracks.isEmpty || _busy
              ? null
              : () => _deleteSelected(data, selectedTracks),
        ),
      ];
    }

    return [
      if (data.tracks.isNotEmpty)
        IconButton(
          tooltip: '播放全部',
          icon: const Icon(Icons.play_circle_outline_rounded),
          onPressed: () => _play(data.tracks, 0),
        ),
      if (data.tracks.isNotEmpty)
        IconButton(
          tooltip: '批量操作',
          icon: const Icon(Icons.checklist_rounded),
          onPressed: () => setState(() => _selecting = true),
        ),
    ];
  }

  Widget _body(_PlaylistData data, List<MediaTrack> selectedTracks) {
    if (data.loading && data.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.error != null && data.tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _retry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (data.tracks.isEmpty) {
      return Center(
        child: Text(
          widget.playlist.source == PlaylistSource.local ? '这个歌单还没有歌曲' : '暂无内容',
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${data.tracks.length} 首',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (widget.playlist.source == PlaylistSource.netease &&
                  widget.playlist.count > data.tracks.length)
                Text(
                  '仅显示前 ${data.tracks.length} 首',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: data.canReorder ? _reorderableList(data) : _plainList(data),
        ),
      ],
    );
  }

  Widget _reorderableList(_PlaylistData data) => ReorderableListView.builder(
    scrollController: _scrollController,
    buildDefaultDragHandles: false,
    padding: const EdgeInsets.only(bottom: 16),
    itemCount: data.tracks.length,
    onReorderItem: _onReorder,
    itemBuilder: (context, index) {
      final track = data.tracks[index];
      return _row(
        context,
        data,
        track,
        index,
        key: ValueKey(track.id),
        showDragHandle: true,
      );
    },
  );

  Widget _plainList(_PlaylistData data) => ListView.builder(
    controller: _scrollController,
    padding: const EdgeInsets.only(bottom: 16),
    itemCount: data.tracks.length + (data.hasMore ? 1 : 0),
    itemBuilder: (context, index) {
      if (index >= data.tracks.length) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      }
      return _row(context, data, data.tracks[index], index);
    },
  );

  Widget _row(
    BuildContext context,
    _PlaylistData data,
    MediaTrack track,
    int index, {
    Key? key,
    bool showDragHandle = false,
  }) {
    final selected = _selected.contains(track.id);
    return KeyedSubtree(
      key: key,
      child: TrackTile(
        track: track,
        showSource: widget.playlist.source == PlaylistSource.local,
        leading: _selecting
            ? Checkbox(value: selected, onChanged: (_) => _toggle(track))
            : null,
        trailing: showDragHandle && _selecting
            ? ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.drag_handle_rounded),
                ),
              )
            : null,
        onTap: () {
          if (_selecting) {
            _toggle(track);
          } else {
            _play(data.tracks, index);
          }
        },
        onLongPress: () {
          if (!_selecting) {
            setState(() {
              _selecting = true;
              _selected.add(track.id);
            });
          } else {
            _toggle(track);
          }
        },
      ),
    );
  }

  void _toggle(MediaTrack track) {
    setState(() {
      if (!_selected.remove(track.id)) _selected.add(track.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _play(List<MediaTrack> tracks, int index) async {
    if (tracks.isEmpty) return;
    _recordRecentPlaylist(tracks);
    await ref
        .read(playerStateProvider.notifier)
        .playTracks(tracks, startIndex: index);
    if (!mounted) return;
    await openPlayerIfEnabled(context, ref);
  }

  void _recordRecentPlaylist(List<MediaTrack> tracks) {
    unawaited(
      ref
          .read(localRecentPlaylistsProvider.notifier)
          .record(
            RecentPlaylist(
              source: widget.playlist.source,
              id: widget.playlist.id,
              title: widget.playlist.title,
              cover: tracks.isEmpty ? '' : tracks.first.cover,
              count: widget.playlist.count,
            ),
          ),
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    try {
      switch (widget.playlist.source) {
        case PlaylistSource.local:
          await ref
              .read(localPlaylistsProvider.notifier)
              .reorder(widget.playlist.id, oldIndex, newIndex);
        case PlaylistSource.netease:
          await ref
              .read(
                neteasePlaylistTracksProvider(widget.playlist.numericId)
                    .notifier,
              )
              .reorder(oldIndex, newIndex);
        case PlaylistSource.bilibili:
          return;
      }
    } on BiliApiException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  Future<void> _addSelected(List<MediaTrack> selectedTracks) async {
    final selection = await showPlaylistPickerSheet(
      context,
      ref,
      tracks: selectedTracks,
      origin: widget.playlist.source,
      exclude: PlaylistSelection(widget.playlist.source, widget.playlist.id),
      title: '添加到歌单',
    );
    if (selection == null || !mounted) return;
    if (selection.isEmpty) return;
    final error = await applyPlaylistSelections(ref, selectedTracks, selection);
    if (!mounted) return;
    if (error != null) {
      _toast(error);
      return;
    }
    _toast('已添加到 ${selection.length} 个歌单');
    _exitSelection();
  }

  Future<void> _deleteSelected(
    _PlaylistData data,
    List<MediaTrack> selectedTracks,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text(
          '确定从「${widget.playlist.title}」中删除选中的 '
          '${selectedTracks.length} 首歌曲吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || data.removeTracks == null) return;

    setState(() => _busy = true);
    try {
      await data.removeTracks!(selectedTracks);
      if (!mounted) return;
      if (widget.playlist.source == PlaylistSource.netease) {
        ref.invalidate(neteasePlaylistsProvider);
      }
      _exitSelection();
      _toast('已删除 ${selectedTracks.length} 首歌曲');
    } on BiliApiException catch (error) {
      if (mounted) _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retry() {
    switch (widget.playlist.source) {
      case PlaylistSource.bilibili:
        ref.invalidate(favMediaProvider(widget.playlist.numericId));
      case PlaylistSource.netease:
        ref.invalidate(
          neteasePlaylistTracksProvider(widget.playlist.numericId),
        );
      case PlaylistSource.local:
        break;
    }
  }

  _PlaylistData _data() {
    switch (widget.playlist.source) {
      case PlaylistSource.local:
        return _localData();
      case PlaylistSource.bilibili:
        return _biliData();
      case PlaylistSource.netease:
        return _neteaseData();
    }
  }

  _PlaylistData _localData() {
    final playlists = ref.watch(localPlaylistsProvider);
    LocalPlaylist? target;
    for (final playlist in playlists) {
      if (playlist.id == widget.playlist.id) {
        target = playlist;
        break;
      }
    }
    final id = widget.playlist.id;
    return _PlaylistData(
      tracks: target?.tracks ?? const [],
      canReorder: true,
      removeTracks: (tracks) =>
          ref.read(localPlaylistsProvider.notifier).removeTracks(id, tracks),
    );
  }

  _PlaylistData _biliData() {
    final id = widget.playlist.numericId;
    final media = ref.watch(favMediaProvider(id));
    final page = media.value;
    return _PlaylistData(
      tracks: page?.items ?? const [],
      loading: media.isLoading && page == null,
      error: media.hasError ? '加载失败：${media.error}' : null,
      hasMore: page?.hasMore ?? false,
      removeTracks: (tracks) async {
        final aids = [
          for (final track in tracks)
            if (track.aid > 0) track.aid,
        ];
        await ref
            .read(favRepositoryProvider)
            .removeFromFolder(mediaId: id, aids: aids);
        ref.invalidate(favMediaProvider(id));
        ref.invalidate(favFoldersProvider);
      },
    );
  }

  _PlaylistData _neteaseData() {
    final id = widget.playlist.numericId;
    final media = ref.watch(neteasePlaylistTracksProvider(id));
    final tracks = media.value;
    // Reordering sends the complete id list; only offer it when the whole
    // playlist was loaded (the API pages at 1000 songs per request).
    final complete =
        tracks != null &&
        (widget.playlist.count <= 0 || tracks.length >= widget.playlist.count);
    return _PlaylistData(
      tracks: tracks ?? const [],
      loading: media.isLoading && tracks == null,
      error: media.hasError ? '加载失败：${media.error}' : null,
      canReorder: complete,
      removeTracks: (tracks) => ref
          .read(neteasePlaylistTracksProvider(id).notifier)
          .removeTracks(tracks),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
