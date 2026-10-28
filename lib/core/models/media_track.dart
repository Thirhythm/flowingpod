import 'json_utils.dart';
import 'track_source.dart';

/// A single playable entry in the app.
///
/// Bilibili entries represent one video part (`P`) and are played as audio
/// only; NetEase entries represent one song. The model is intentionally
/// serialisable so the current queue can be restored after the app restarts.
class MediaTrack {
  const MediaTrack({
    this.source = TrackSource.bilibili,
    this.bvid = '',
    this.aid = 0,
    this.cid = 0,
    required this.title,
    required this.artist,
    required this.cover,
    this.songId = 0,
    this.artistId = 0,
    this.duration = Duration.zero,
    this.page = 1,
    this.partTitle,
    this.playCount = 0,
    this.vip = false,
  });

  final TrackSource source;
  final String bvid;
  final int aid;
  final int cid;
  final String title;
  final String artist;
  final String cover;

  /// NetEase song id; zero for Bilibili tracks.
  final int songId;
  final int artistId;
  final Duration duration;

  /// Part index inside a multi-part video (`pages[].page`).
  final int page;

  /// Part name (`pages[].part`) when the video has multiple parts.
  final String? partTitle;

  final int playCount;

  /// NetEase VIP-only song (`fee == 1`); `false` for Bilibili tracks.
  final bool vip;

  bool get isNetease => source == TrackSource.netease;

  /// A stable identity for a queue entry.
  String get id => isNetease ? 'netease:$songId' : '$bvid:$cid';

  /// Identity of the video part, available even before the part id is known.
  ///
  /// Queue entries coming from search or a favourite folder only carry a
  /// [bvid]; the player fills in [cid] once the video detail is loaded, so
  /// comparing parts must not depend on [cid].
  String get partKey => isNetease ? id : '$bvid:$page';

  /// `true` once the entry can be played without resolving an id first.
  bool get isResolved => isNetease ? songId > 0 : cid > 0;

  /// Whether the entry can be stored in a playlist.
  bool get canFavorite => isNetease ? songId > 0 : aid > 0;

  bool get hasParts => partTitle != null && partTitle!.isNotEmpty;

  /// Title including the part name when it adds information.
  String get displayTitle =>
      hasParts && partTitle != title ? '$title · $partTitle' : title;

  factory MediaTrack.fromJson(Map<String, dynamic> json) => MediaTrack(
    source: TrackSource.fromStorage(json['source']),
    bvid: JsonUtils.string(json['bvid']),
    aid: JsonUtils.integer(json['aid']),
    cid: JsonUtils.integer(json['cid']),
    title: JsonUtils.string(json['title']),
    artist: JsonUtils.string(json['artist']),
    cover: JsonUtils.string(json['cover']),
    songId: JsonUtils.integer(json['songId']),
    artistId: JsonUtils.integer(json['artistId']),
    duration: Duration(milliseconds: JsonUtils.integer(json['durationMs'])),
    page: JsonUtils.integer(json['page'], fallback: 1),
    partTitle: JsonUtils.nullableString(json['partTitle']),
    playCount: JsonUtils.integer(json['playCount']),
    vip: json['vip'] == true,
  );

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'bvid': bvid,
    'aid': aid,
    'cid': cid,
    'title': title,
    'artist': artist,
    'cover': cover,
    'songId': songId,
    'artistId': artistId,
    'durationMs': duration.inMilliseconds,
    'page': page,
    'partTitle': partTitle,
    'playCount': playCount,
    'vip': vip,
  };

  MediaTrack copyWith({
    TrackSource? source,
    String? bvid,
    int? aid,
    int? cid,
    String? title,
    String? artist,
    String? cover,
    int? songId,
    int? artistId,
    Duration? duration,
    int? page,
    String? partTitle,
    int? playCount,
    bool? vip,
  }) => MediaTrack(
    source: source ?? this.source,
    bvid: bvid ?? this.bvid,
    aid: aid ?? this.aid,
    cid: cid ?? this.cid,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    cover: cover ?? this.cover,
    songId: songId ?? this.songId,
    artistId: artistId ?? this.artistId,
    duration: duration ?? this.duration,
    page: page ?? this.page,
    partTitle: partTitle ?? this.partTitle,
    playCount: playCount ?? this.playCount,
    vip: vip ?? this.vip,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaTrack &&
      other.source == source &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.songId == songId;

  @override
  int get hashCode => Object.hash(source, bvid, cid, songId);

  @override
  String toString() => 'MediaTrack(${source.name}/$id, $title)';
}
