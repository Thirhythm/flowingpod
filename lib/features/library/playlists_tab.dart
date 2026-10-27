import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/local_playlist.dart';
import 'package:flowingpod/core/models/netease_playlist.dart';
import 'package:flowingpod/core/models/playlist_ref.dart';
import 'package:flowingpod/features/library/playlist_detail_page.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_playlists_controller.dart';
import 'package:flowingpod/state/netease_auth_controller.dart';
import 'package:flowingpod/state/netease_library_controllers.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flowingpod/widgets/cover_image.dart';
import 'package:flowingpod/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playlists tab of 媒体库: local playlists plus the two cloud services in
/// collapsible sections, each shown only while signed in.
class PlaylistsTab extends ConsumerWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localPlaylistsProvider);
    final biliLoggedIn = ref.watch(
      authControllerProvider.select((state) => state.isLoggedIn),
    );
    final neteaseLoggedIn = ref.watch(
      neteaseAuthProvider.select((state) => state.isLoggedIn),
    );

    return RefreshIndicator(
      onRefresh: () =>
          _refresh(ref, bili: biliLoggedIn, netease: neteaseLoggedIn),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SectionHeader(
            title: '本地歌单',
            action: IconButton(
              tooltip: '新建本地歌单',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _createLocal(context, ref),
            ),
          ),
          for (final playlist in local) _localTile(context, ref, playlist),
          if (biliLoggedIn) ...[
            _CloudSection(
              title: '哔哩哔哩',
              addLabel: '新建收藏夹',
              onAdd: () => _createBiliFolder(context, ref),
              child: _BiliFolders(),
            ),
          ],
          if (neteaseLoggedIn) ...[
            _CloudSection(
              title: '网易云音乐',
              addLabel: '新建歌单',
              onAdd: () => _createNeteasePlaylist(context, ref),
              child: const _NeteasePlaylists(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refresh(
    WidgetRef ref, {
    required bool bili,
    required bool netease,
  }) async {
    final futures = <Future<void>>[];
    if (bili) {
      futures.add(ref.read(favFoldersProvider.notifier).reload());
    }
    if (netease) {
      futures.add(ref.read(neteasePlaylistsProvider.notifier).reload());
    }
    await Future.wait(futures);
  }

  Widget _localTile(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) {
    final reference = PlaylistRef(
      source: PlaylistSource.local,
      id: playlist.id,
      title: playlist.name,
      count: playlist.tracks.length,
    );
    return ListTile(
      leading: playlist.isLiked
          ? const _LeadingIcon(
              icon: Icons.favorite_rounded,
              color: Color(0xFFE54545),
            )
          : playlist.cover.isEmpty
          ? const _LeadingIcon(icon: Icons.queue_music_rounded)
          : CoverImage(url: playlist.cover, size: 44, radius: 8),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.tracks.length} 首'),
      onLongPress: playlist.isLiked
          ? null
          : () => _localActions(context, ref, playlist),
      onTap: () => _open(context, reference),
    );
  }

  Future<void> _localActions(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) async {
    final action = await _showTileMenu(context, playlist.name);
    if (action == null || !context.mounted) return;
    switch (action) {
      case _TileAction.rename:
        await _renameLocal(context, ref, playlist);
      case _TileAction.delete:
        await _deleteLocal(context, ref, playlist);
    }
  }

  Future<void> _renameLocal(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) async {
    final name = await _askName(
      context,
      title: '重命名歌单',
      initialValue: playlist.name,
      confirmLabel: '保存',
    );
    if (name == null) return;
    await ref.read(localPlaylistsProvider.notifier).rename(playlist.id, name);
  }

  void _open(BuildContext context, PlaylistRef reference) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(playlist: reference),
      ),
    );
  }

  Future<void> _createLocal(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, title: '新建歌单');
    if (name == null) return;
    await ref.read(localPlaylistsProvider.notifier).create(name);
  }

  Future<void> _createBiliFolder(BuildContext context, WidgetRef ref) async {
    final name = await _askName(context, title: '新建收藏夹');
    if (name == null) return;
    try {
      await ref.read(favRepositoryProvider).createFolder(name);
      ref.invalidate(favFoldersProvider);
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }

  Future<void> _createNeteasePlaylist(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final name = await _askName(context, title: '新建网易云歌单');
    if (name == null) return;
    try {
      await ref.read(neteaseRepositoryProvider).createPlaylist(name);
      await ref.read(neteasePlaylistsProvider.notifier).reload();
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }

  Future<void> _deleteLocal(
    BuildContext context,
    WidgetRef ref,
    LocalPlaylist playlist,
  ) async {
    final confirmed = await _confirm(
      context,
      title: '删除歌单',
      message: '确定删除「${playlist.name}」吗？歌单中的歌曲不会被删除。',
    );
    if (!confirmed) return;
    await ref.read(localPlaylistsProvider.notifier).remove(playlist.id);
  }
}

/// Entries the long-press menu of a playlist row can return.
enum _TileAction { rename, delete }

/// Shows the long-press menu for the row named [title].
Future<_TileAction?> _showTileMenu(BuildContext context, String title) =>
    showModalBottomSheet<_TileAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _TileActionSheet(title: title),
    );

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String? initialValue,
  String confirmLabel = '创建',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _CreateNameDialog(
      title: title,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
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
  return result ?? false;
}

class _TileActionSheet extends StatelessWidget {
  const _TileActionSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline_rounded),
          title: const Text('重命名'),
          onTap: () => Navigator.of(context).pop(_TileAction.rename),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('删除'),
          onTap: () => Navigator.of(context).pop(_TileAction.delete),
        ),
      ],
    ),
  );
}

/// Collapsible cloud section with a create entry at the top of its contents.
class _CloudSection extends StatelessWidget {
  const _CloudSection({
    required this.title,
    required this.addLabel,
    required this.onAdd,
    required this.child,
  });

  final String title;
  final String addLabel;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: Text(addLabel),
          onTap: onAdd,
        ),
        child,
      ],
    );
  }
}

class _BiliFolders extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(favFoldersProvider);
    return folders.when(
      loading: () => const _LoadingRow(),
      error: (error, _) => _ErrorRow(
        message: '收藏夹加载失败：$error',
        onRetry: () => ref.read(favFoldersProvider.notifier).reload(),
      ),
      data: (list) {
        if (list.isEmpty) return const _EmptyRow(message: '暂无收藏夹');
        return Column(
          children: [for (final folder in list) _BiliTile(folder: folder)],
        );
      },
    );
  }
}

class _BiliTile extends ConsumerWidget {
  const _BiliTile({required this.folder});

  final FavFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = PlaylistRef(
      source: PlaylistSource.bilibili,
      id: '${folder.id}',
      title: folder.title,
      count: folder.mediaCount,
    );
    return ListTile(
      leading: const _LeadingIcon(icon: Icons.folder_rounded),
      title: Text(folder.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${folder.mediaCount} 个内容'),
      onLongPress: folder.isDefault ? null : () => _actions(context, ref),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailPage(playlist: reference),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final action = await _showTileMenu(context, folder.title);
    if (action == null || !context.mounted) return;
    switch (action) {
      case _TileAction.rename:
        await _rename(context, ref);
      case _TileAction.delete:
        await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await _askName(
      context,
      title: '重命名收藏夹',
      initialValue: folder.title,
      confirmLabel: '保存',
    );
    if (name == null) return;
    try {
      await ref.read(favRepositoryProvider).renameFolder(folder.id, name);
      ref.invalidate(favFoldersProvider);
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('确定删除「${folder.title}」吗？'),
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
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(favRepositoryProvider).deleteFolder(folder.id);
      ref.invalidate(favFoldersProvider);
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }
}

class _NeteasePlaylists extends ConsumerWidget {
  const _NeteasePlaylists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(neteasePlaylistsProvider);
    return playlists.when(
      loading: () => const _LoadingRow(),
      error: (error, _) => _ErrorRow(
        message: '网易云歌单加载失败：$error',
        onRetry: () => ref.read(neteasePlaylistsProvider.notifier).reload(),
      ),
      data: (list) {
        if (list.isEmpty) return const _EmptyRow(message: '暂无歌单');
        return Column(
          children: [
            for (final playlist in list) _NeteaseTile(playlist: playlist),
          ],
        );
      },
    );
  }
}

class _NeteaseTile extends ConsumerWidget {
  const _NeteaseTile({required this.playlist});

  final NeteasePlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reference = PlaylistRef(
      source: PlaylistSource.netease,
      id: '${playlist.id}',
      title: playlist.name,
      count: playlist.trackCount,
    );
    return ListTile(
      leading: playlist.isLiked
          ? const _LeadingIcon(
              icon: Icons.favorite_rounded,
              color: Color(0xFFE54545),
            )
          : CoverImage(url: playlist.coverUrl, size: 44, radius: 8),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.trackCount} 首'),
      onLongPress: playlist.isLiked ? null : () => _actions(context, ref),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistDetailPage(playlist: reference),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final action = await _showTileMenu(context, playlist.name);
    if (action == null || !context.mounted) return;
    switch (action) {
      case _TileAction.rename:
        await _rename(context, ref);
      case _TileAction.delete:
        await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await _askName(
      context,
      title: '重命名歌单',
      initialValue: playlist.name,
      confirmLabel: '保存',
    );
    if (name == null) return;
    try {
      await ref
          .read(neteaseRepositoryProvider)
          .renamePlaylist(playlist.id, name);
      await ref.read(neteasePlaylistsProvider.notifier).reload();
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除网易云歌单「${playlist.name}」吗？'),
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
    if (!(confirmed ?? false)) return;
    try {
      await ref.read(neteaseRepositoryProvider).deletePlaylist(playlist.id);
      await ref.read(neteasePlaylistsProvider.notifier).reload();
    } on BiliApiException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 22,
      backgroundColor: scheme.secondaryContainer,
      child: Icon(icon, color: color ?? scheme.onSecondaryContainer, size: 22),
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
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      children: [
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
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

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );

class _CreateNameDialog extends StatefulWidget {
  const _CreateNameDialog({
    required this.title,
    this.initialValue,
    this.confirmLabel = '创建',
  });

  final String title;
  final String? initialValue;
  final String confirmLabel;

  @override
  State<_CreateNameDialog> createState() => _CreateNameDialogState();
}

class _CreateNameDialogState extends State<_CreateNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initialValue?.length ?? 0,
        );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(
        labelText: '名称',
        counterText: '',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
