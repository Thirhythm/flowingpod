import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/bili_endpoints.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/paged_result.dart';
import 'package:flowingpod/core/utils/text_utils.dart';

/// Video search sorted by relevance, with pagination.
class SearchRepository {
  SearchRepository(this._client);

  final BiliClient _client;

  static const int pageSize = 20;

  Future<PagedResult<MediaTrack>> searchVideos({
    required String keyword,
    int page = 1,
  }) async {
    final response = await _client.getJson(
      BiliEndpoints.searchType,
      signed: true,
      query: {
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
        'order': 'totalrank',
        'platform': 'pc',
      },
    );
    final data = JsonUtils.map(response['data']);
    final items = <MediaTrack>[
      for (final result in JsonUtils.list(data['result']))
        if (JsonUtils.string(result['bvid']).isNotEmpty) _toTrack(result),
    ];

    final numPages = JsonUtils.integer(data['numPages']);
    return PagedResult(
      items: items,
      page: JsonUtils.integer(data['page'], fallback: page),
      hasMore: page < numPages && items.isNotEmpty,
      total: JsonUtils.integer(data['numResults']),
    );
  }

  MediaTrack _toTrack(Map<String, dynamic> json) => MediaTrack(
    bvid: JsonUtils.string(json['bvid']),
    aid: JsonUtils.integer(json['aid']),
    // The part id is unknown until the video detail is loaded.
    cid: 0,
    title: TextUtils.stripHtml(json['title']),
    artist: TextUtils.stripHtml(json['author']),
    cover: JsonUtils.string(json['pic']),
    artistId: JsonUtils.integer(json['mid']),
    duration: JsonUtils.flexibleDuration(json['duration']),
    playCount: JsonUtils.integer(json['play']),
  );
}
