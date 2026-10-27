import 'json_utils.dart';

/// A NetEase Cloud Music playlist belonging to (or collected by) the account.
class NeteasePlaylist {
  const NeteasePlaylist({
    required this.id,
    required this.name,
    this.userId = 0,
    this.coverUrl = '',
    this.trackCount = 0,
    this.specialType = 0,
    this.subscribed = false,
  });

  final int id;
  final String name;
  final int userId;
  final String coverUrl;
  final int trackCount;

  /// `5` marks the account's 我喜欢的音乐 playlist.
  final int specialType;

  /// `true` when the playlist belongs to someone else and was collected.
  final bool subscribed;

  bool get isLiked => specialType == 5;

  factory NeteasePlaylist.fromJson(Map<String, dynamic> json) =>
      NeteasePlaylist(
        id: JsonUtils.integer(json['id']),
        name: JsonUtils.string(json['name'], fallback: '未命名歌单'),
        userId: JsonUtils.integer(json['userId']),
        coverUrl: JsonUtils.string(json['coverImgUrl']),
        trackCount: JsonUtils.integer(json['trackCount']),
        specialType: JsonUtils.integer(json['specialType']),
        subscribed: JsonUtils.boolean(json['subscribed']),
      );
}
