/// Where a playlist lives.
enum PlaylistSource { local, bilibili, netease }

/// Lightweight reference to a playlist, shared by the library lists and the
/// playlist detail page.
class PlaylistRef {
  const PlaylistRef({
    required this.source,
    required this.id,
    required this.title,
    this.count = 0,
  });

  final PlaylistSource source;

  /// Local playlist id, Bilibili media id or NetEase playlist id.
  final String id;
  final String title;
  final int count;

  int get numericId => int.tryParse(id) ?? 0;

  @override
  bool operator ==(Object other) =>
      other is PlaylistRef && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}
