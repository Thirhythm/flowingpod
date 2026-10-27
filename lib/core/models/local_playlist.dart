import 'json_utils.dart';
import 'media_track.dart';

/// A playlist stored on this device.
class LocalPlaylist {
  const LocalPlaylist({
    required this.id,
    required this.name,
    this.tracks = const [],
  });

  final String id;
  final String name;
  final List<MediaTrack> tracks;

  bool get isLiked => id == LocalPlaylist.likedId;

  /// Cover taken from the first track; empty when the playlist is empty.
  String get cover => tracks.isEmpty ? '' : tracks.first.cover;

  LocalPlaylist copyWith({String? name, List<MediaTrack>? tracks}) =>
      LocalPlaylist(
        id: id,
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
      );

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) => LocalPlaylist(
    id: JsonUtils.string(json['id']),
    name: JsonUtils.string(json['name'], fallback: '未命名歌单'),
    tracks: [
      for (final item in JsonUtils.list(json['tracks']))
        MediaTrack.fromJson(item),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': [for (final track in tracks) track.toJson()],
  };

  /// Id of the built-in, undeletable 我喜欢的音乐 playlist.
  static const String likedId = 'liked';

  /// Name of the built-in playlist.
  static const String likedName = '我喜欢的音乐';
}
