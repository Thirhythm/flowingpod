import 'json_utils.dart';
import 'playlist_ref.dart';

/// A playlist played from recently, feeding the home page's 最近播放 shortcuts.
///
/// It keeps just enough of the playlist — its identity plus the cover seen when
/// it was played — to offer it again afterwards, for any of the three sources.
class RecentPlaylist {
  const RecentPlaylist({
    required this.source,
    required this.id,
    required this.title,
    required this.cover,
    this.count = 0,
  });

  final PlaylistSource source;

  /// Local playlist id, Bilibili media id or NetEase playlist id.
  final String id;
  final String title;

  /// Cover of the playlist's first entry, captured when it was played.
  final String cover;
  final int count;

  /// The playlist this shortcut opens again.
  PlaylistRef toRef() =>
      PlaylistRef(source: source, id: id, title: title, count: count);

  factory RecentPlaylist.fromJson(Map<String, dynamic> json) => RecentPlaylist(
    source: _sourceFrom(json['source']),
    id: JsonUtils.string(json['id']),
    title: JsonUtils.string(json['title'], fallback: '未命名歌单'),
    cover: JsonUtils.string(json['cover']),
    // `mediaCount` is the field name older builds stored.
    count: JsonUtils.integer(json['count'] ?? json['mediaCount']),
  );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'id': id,
    'title': title,
    'cover': cover,
    'count': count,
  };

  static PlaylistSource _sourceFrom(Object? raw) {
    final name = JsonUtils.string(raw);
    for (final source in PlaylistSource.values) {
      if (source.name == name) return source;
    }
    return PlaylistSource.bilibili;
  }

  @override
  bool operator ==(Object other) =>
      other is RecentPlaylist && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => 'RecentPlaylist(${source.name}, $id, $title)';
}
