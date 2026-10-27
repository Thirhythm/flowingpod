import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/bili_endpoints.dart';
import 'package:flowingpod/core/models/fav_folder.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/paged_result.dart';

/// Reads the signed-in user's favourite folders and their contents.
class FavRepository {
  FavRepository(this._client);

  final BiliClient _client;

  static const int pageSize = 20;

  /// Fetches every folder created by [mid].
  Future<List<FavFolder>> fetchFolders(int mid) async {
    final response = await _client.getJson(
      BiliEndpoints.favFolderCreated,
      requireLogin: true,
      query: {'up_mid': mid, 'type': 0, 'web_location': '333.1387'},
    );
    final data = response['data'];
    if (data is! Map) return const [];
    return [
      for (final folder in JsonUtils.list(data['list']))
        FavFolder.fromJson(folder),
    ];
  }

  /// Creates a favourite folder and returns its media id.
  Future<int> createFolder(String title) async {
    final response = await _client.postForm(BiliEndpoints.favFolderAdd, {
      'title': title,
      'description': '',
      'privacy': 0,
      'cover': '',
      'csrf': _csrf(),
    });
    final id = JsonUtils.integer(JsonUtils.map(response['data'])['id']);
    if (id <= 0) {
      throw const BiliApiException(code: -1, message: '创建收藏夹失败');
    }
    return id;
  }

  /// Renames a favourite folder created by the user.
  Future<void> renameFolder(int mediaId, String title) async {
    await _client.postForm(BiliEndpoints.favFolderEdit, {
      'media_id': mediaId,
      'title': title,
      'csrf': _csrf(),
    });
  }

  /// Deletes a favourite folder created by the user.
  Future<void> deleteFolder(int mediaId) async {
    await _client.postForm(BiliEndpoints.favFolderDel, {
      'media_ids': mediaId,
      'platform': 'web',
      'csrf': _csrf(),
    });
  }

  /// Fetches the videos stored in a single folder.
  Future<PagedResult<MediaTrack>> fetchFolderMedia({
    required int mediaId,
    int page = 1,
  }) async {
    final response = await _client.getJson(
      BiliEndpoints.favResourceList,
      requireLogin: true,
      query: {
        'media_id': mediaId,
        'pn': page,
        'ps': pageSize,
        'order': 'mtime',
        'type': 0,
        'tid': 0,
        'platform': 'web',
      },
    );
    final data = JsonUtils.map(response['data']);
    final tracks = <MediaTrack>[];
    for (final media in JsonUtils.list(data['medias'])) {
      // `attr != 0` marks invalidated (deleted/private) entries.
      final attr = JsonUtils.integer(media['attr']);
      if (attr != 0) continue;
      final bvid = JsonUtils.string(media['bvid']);
      if (bvid.isEmpty) continue;
      final upper = JsonUtils.map(media['upper']);
      final countInfo = JsonUtils.map(media['cnt_info']);
      tracks.add(
        MediaTrack(
          bvid: bvid,
          aid: JsonUtils.integer(media['id']),
          // Resolved from the video detail when playback starts.
          cid: 0,
          title: JsonUtils.string(media['title'], fallback: '未知内容'),
          artist: JsonUtils.string(upper['name'], fallback: '未知作者'),
          cover: JsonUtils.string(media['cover']),
          artistId: JsonUtils.integer(upper['mid']),
          duration: JsonUtils.durationFromSeconds(media['duration']),
          playCount: JsonUtils.integer(countInfo['play']),
        ),
      );
    }

    return PagedResult(
      items: tracks,
      page: page,
      hasMore: JsonUtils.boolean(data['has_more']),
    );
  }

  /// Adds the video to [addTo] and/or removes it from [removeFrom].
  Future<void> dealResources({
    required int aid,
    List<int> addTo = const [],
    List<int> removeFrom = const [],
  }) async {
    if (aid <= 0 || (addTo.isEmpty && removeFrom.isEmpty)) return;
    try {
      await _client.postForm(BiliEndpoints.favResourceDeal, {
        'rid': aid,
        'type': 2,
        'add_media_ids': addTo.join(','),
        'del_media_ids': removeFrom.join(','),
        'platform': 'web',
        'csrf': _csrf(),
      });
    } on BiliApiException catch (error) {
      // 11201: already stored in that folder, 11202: already removed.
      if (error.code == 11201 || error.code == 11202) return;
      rethrow;
    }
  }

  /// Removes videos from a folder.
  Future<void> removeFromFolder({
    required int mediaId,
    required List<int> aids,
  }) async {
    if (aids.isEmpty) return;
    await _client.postForm(BiliEndpoints.favResourceBatchDel, {
      'resources': [for (final aid in aids) '$aid:2'].join(','),
      'media_id': mediaId,
      'platform': 'web',
      'csrf': _csrf(),
    });
  }

  String _csrf() {
    final token = _client.cookies.csrfToken;
    if (token == null || token.isEmpty) {
      throw const BiliApiException(code: -101, message: '登录状态已失效，请重新登录');
    }
    return token;
  }
}
