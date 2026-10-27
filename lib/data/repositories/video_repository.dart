import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/bili_endpoints.dart';
import 'package:flowingpod/core/models/audio_stream.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:flowingpod/core/models/video_detail.dart';

/// Reads video metadata and resolves audio-only play URLs.
class VideoRepository {
  VideoRepository(this._client);

  final BiliClient _client;

  /// `fnval` requesting DASH plus Dolby and Hi-Res audio when available.
  static const int _dashFnval = 4048;

  /// Loads the full metadata (including every part) of a video.
  Future<VideoDetail> fetchDetail({String? bvid, int? aid}) async {
    final response = await _client.getJson(
      BiliEndpoints.videoView,
      query: {
        if (bvid != null && bvid.isNotEmpty) 'bvid': bvid,
        if (aid != null && aid > 0) 'aid': aid,
      },
    );
    final detail = VideoDetail.fromJson(JsonUtils.map(response['data']));
    if (detail.bvid.isEmpty || detail.parts.isEmpty) {
      throw const BiliApiException(
        code: -404,
        message: '视频不存在或已被删除',
        path: BiliEndpoints.videoView,
      );
    }
    return detail;
  }

  /// Resolves the audio streams of a single video part.
  Future<PlaybackSource> fetchPlaybackSource({
    required String bvid,
    required int cid,
  }) async {
    if (bvid.isEmpty || cid <= 0) {
      throw const BiliApiException(code: -400, message: '无效的视频标识');
    }
    final response = await _client.getJson(
      BiliEndpoints.videoPlayUrl,
      signed: true,
      query: {
        'bvid': bvid,
        'cid': cid,
        'qn': 80,
        'fnval': _dashFnval,
        'fnver': 0,
        'fourk': 1,
        'platform': 'pc',
        'high_quality': 1,
        'try_look': 1,
        'otype': 'json',
      },
    );
    final source = PlaybackSource.fromPlayUrl(JsonUtils.map(response['data']));
    if (source.isEmpty) {
      throw const BiliApiException(
        code: -1,
        message: '无法获取音频流，该视频可能没有音轨或需要登录',
        path: BiliEndpoints.videoPlayUrl,
      );
    }
    return source;
  }
}
