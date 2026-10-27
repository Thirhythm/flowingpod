import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_playlist.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flowingpod/state/netease_library_controllers.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One selectable playlist.
class PlaylistSelection {
  const PlaylistSelection(this.source, this.id);

  final PlaylistSource source;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is PlaylistSelection && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}

/// Shows the playlist picker and returns the final selection, or `null` when
/// the sheet is dismissed.
Future<Set<PlaylistSelection>?> showPlaylistPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<MediaTrack> tracks,
  required PlaylistSource origin,
  Set<PlaylistSelection> initialSelection = const {},
  PlaylistSelection? exclude,
  String title = '添加到歌单',
  String? subtitle,
}) => showModalBottomSheet<Set<PlaylistSelection>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _PlaylistPickerSheet(
    tracks: tracks,
    origin: origin,
    initialSelection: initialSelection,
    exclude: exclude,
    title: title,
    subtitle: subtitle,
  ),
);

/// Applies the picker result: adds to newly checked playlists, removes the
/// track from local playlists that were unchecked, then reports failures.
Future<String?> applyPlaylistSelections(
  WidgetRef ref,
  List<MediaTrack> tracks,
  Set<PlaylistSelection> selected, {
  Set<PlaylistSelection> initial = const {},
}) async {
  try {
    final localPlaylists = ref.read(localPlaylistsProvider);
    for (final playlist in localPlaylists) {
      final selection = PlaylistSelection(PlaylistSource.local, playlist.id);
      final wasSelected = initial.contains(selection);
      final isSelected = selected.contains(selection);
      if (isSelected && !wasSelected) {
        await ref
            .read(localPlaylistsProvider.notifier)
            .addTracks(playlist.id, tracks);
      } else if (!isSelected && wasSelected) {
        await ref
            .read(localPlaylistsProvider.notifier)
            .removeTracks(playlist.id, tracks);
      }
    }

    final biliFolders = {
      for (final selection in selected)
        if (selection.source == PlaylistSource.bilibili)
          int.tryParse(selection.id) ?? 0,
    }..remove(0);
    if (biliFolders.isNotEmpty) {
      final repository = ref.read(favRepositoryProvider);
      for (final track in tracks) {
        if (track.aid <= 0) continue;
        await repository.dealResources(
          aid: track.aid,
          addTo: biliFolders.toList(),
        );
      }
      ref.invalidate(favFoldersProvider);
      for (final folderId in biliFolders) {
        ref.invalidate(favMediaProvider(folderId));
      }
    }

    final neteasePlaylists = {
      for (final selection in selected)
        if (selection.source == PlaylistSource.netease)
          int.tryParse(selection.id) ?? 0,
    }..remove(0);
    if (neteasePlaylists.isNotEmpty) {
      final songIds = [
        for (final track in tracks)
          if (track.songId > 0) track.songId,
      ];
      if (songIds.isNotEmpty) {
        final repository = ref.read(neteaseRepositoryProvider);
        for (final playlistId in neteasePlaylists) {
          await repository.addTracksToPlaylist(playlistId, songIds);
        }
        ref.invalidate(neteasePlaylistsProvider);
        for (final playlistId in neteasePlaylists) {
          ref.invalidate(neteasePlaylistTracksProvider(playlistId));
        }
      }
    }
    return null;
  } on BiliApiException catch (error) {
    return error.message;
  }
}

class _PlaylistPickerSheet extends ConsumerStatefulWidget {
  const _PlaylistPickerSheet({
    required this.tracks,
    required this.origin,
    required this.initialSelection,
    this.exclude,
    required this.title,
    this.subtitle,
  });

  final List<MediaTrack> tracks;
  final PlaylistSource origin;
  final Set<PlaylistSelection> initialSelection;
  final PlaylistSelection? exclude;
  final String title;
  final String? subtitle;

  @override
  ConsumerState<_PlaylistPickerSheet> createState() =>
      _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<_PlaylistPickerSheet> {
  late final Set<PlaylistSelection> _selected = {...widget.initialSelection};

  bool _show(String id, PlaylistSource source) =>
      widget.exclude != PlaylistSelection(source, id);

  void _toggle(PlaylistSelection selection) {
    setState(() {
      if (!_selected.remove(selection)) _selected.add(selection);
    });
  }

  @override
  Widget build(BuildContext context) {
    final biliLoggedIn = ref.watch(
      authControllerProvider.select((state) => state.isLoggedIn),
    );
    final neteaseLoggedIn = ref.watch(
      neteaseAuthProvider.select((state) => state.isLoggedIn),
    );
    final showBili = widget.origin == PlaylistSource.bilibili && biliLoggedIn;
    final showNetease =
        widget.origin == PlaylistSource.netease && neteaseLoggedIn;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                _sectionTitle(context, '本地歌单'),
                _localPlaylists(),
                if (showBili) ...[
                  _sectionTitle(context, '哔哩哔哩'),
                  _biliFolders(),
                ],
                if (showNetease) ...[
                  _sectionTitle(context, '网易云音乐'),
                  _neteasePlaylists(),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(_selected),
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text(
                  _selected.isEmpty ? '未选择歌单' : '保存到 ${_selected.length} 个歌单',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final first = widget.tracks.first;
    final label = widget.tracks.length == 1
        ? first.displayTitle
        : '${widget.tracks.length} 首歌曲';
    return ListTile(
      leading: CoverImage(url: first.cover, size: 44, radius: 6),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(widget.subtitle ?? widget.title),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Widget _localPlaylists() {
    final playlists = ref.watch(localPlaylistsProvider);
    return Column(
      children: [
        for (final playlist in playlists)
          if (_show(playlist.id, PlaylistSource.local))
            _tile(
              playlist: playlist,
              checked: _selected.contains(
                PlaylistSelection(PlaylistSource.local, playlist.id),
              ),
              onChanged: () =>
                  _toggle(PlaylistSelection(PlaylistSource.local, playlist.id)),
            ),
      ],
    );
  }

  Widget _tile({
    required LocalPlaylist playlist,
    required bool checked,
    required VoidCallback onChanged,
  }) => ListTile(
    leading: playlist.isLiked
        ? const Icon(Icons.favorite_rounded)
        : const Icon(Icons.queue_music_rounded),
    title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('${playlist.tracks.length} 首'),
    trailing: Checkbox(value: checked, onChanged: (_) => onChanged()),
    onTap: onChanged,
  );

  Widget _biliFolders() {
    final folders = ref.watch(favFoldersProvider);
    return folders.when(
      loading: () => const _LoadingRow(),
      error: (error, _) => _ErrorRow(message: '$error'),
      data: (list) {
        final visible = [
          for (final folder in list)
            if (_show('${folder.id}', PlaylistSource.bilibili)) folder,
        ];
        if (visible.isEmpty) return const _EmptyRow(message: '暂无收藏夹');
        return Column(
          children: [for (final folder in visible) _biliTile(folder)],
        );
      },
    );
  }

  Widget _biliTile(FavFolder folder) {
    final selection = PlaylistSelection(
      PlaylistSource.bilibili,
      '${folder.id}',
    );
    return ListTile(
      leading: const Icon(Icons.folder_rounded),
      title: Text(folder.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${folder.mediaCount} 个内容'),
      trailing: Checkbox(
        value: _selected.contains(selection),
        onChanged: (_) => _toggle(selection),
      ),
      onTap: () => _toggle(selection),
    );
  }

  Widget _neteasePlaylists() {
    final playlists = ref.watch(neteasePlaylistsProvider);
    return playlists.when(
      loading: () => const _LoadingRow(),
      error: (error, _) => _ErrorRow(message: '$error'),
      data: (list) {
        final visible = [
          for (final playlist in list)
            if (_show('${playlist.id}', PlaylistSource.netease)) playlist,
        ];
        if (visible.isEmpty) return const _EmptyRow(message: '暂无歌单');
        return Column(
          children: [for (final playlist in visible) _neteaseTile(playlist)],
        );
      },
    );
  }

  Widget _neteaseTile(NeteasePlaylist playlist) {
    final selection = PlaylistSelection(
      PlaylistSource.netease,
      '${playlist.id}',
    );
    return ListTile(
      leading: playlist.isLiked
          ? const Icon(Icons.favorite_rounded)
          : CoverImage(url: playlist.coverUrl, size: 40, radius: 6),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.trackCount} 首'),
      trailing: Checkbox(
        value: _selected.contains(selection),
        onChanged: (_) => _toggle(selection),
      ),
      onTap: () => _toggle(selection),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) => const Padding(
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

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Text(message, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
