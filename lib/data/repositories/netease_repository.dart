import 'dart:convert';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/netease_client.dart';
import 'package:flowingpod/core/api/netease_endpoints.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_playlist.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/core/models/netease_user.dart';
import 'package:flowingpod/core/models/paged_result.dart';
import 'package:flowingpod/core/models/track_source.dart';

enum NeteaseQrStatus { waiting, scanned, expired, success, failed }

class NeteaseQrResult {
  const NeteaseQrResult(this.status, {this.message});

  final NeteaseQrStatus status;
  final String? message;
}

/// A resolved stream together with the quality the backend actually served.
class NeteaseSongUrl {
  const NeteaseSongUrl({required this.url, required this.level});

  final String url;

  /// Quality delivered by the API; `null` when the value is not recognised.
  final NeteaseQuality? level;
}

/// NetEase account, search, song and playlist operations.
///
/// Every request goes straight to the web API through [NeteaseClient], which
/// encrypts it locally; no intermediate service is involved.
class NeteaseRepository {
  NeteaseRepository(this._client);

  final NeteaseClient _client;

  static const int pageSize = 30;

  bool get isLoggedIn => _client.isLoggedIn;

  // --- Account ------------------------------------------------------------

  Future<NeteaseUser?> fetchCurrentUser() async {
    if (!isLoggedIn) return null;
    final response = _client.expectOk(
      await _client.request(NeteaseEndpoints.account, requireLogin: true),
      NeteaseEndpoints.account,
    );
    final profile = response['profile'];
    if (profile is! Map) return null;
    return NeteaseUser.fromProfile(
      profile.map((key, value) => MapEntry('$key', value)),
    );
  }

  Future<void> logout() async {
    try {
      if (isLoggedIn) {
        await _client.request(NeteaseEndpoints.logout);
      }
    } catch (_) {
      // The remote session is best-effort; local cookies are cleared below.
    } finally {
      await _client.cookies.clear();
    }
  }

  // --- QR login -----------------------------------------------------------

  Future<String> createQrKey() async {
    final response = _client.expectOk(
      await _client.request(NeteaseEndpoints.qrKey, data: const {'type': 3}),
      NeteaseEndpoints.qrKey,
    );
    final key = JsonUtils.string(response['unikey']);
    if (key.isEmpty) {
      throw const BiliApiException(
        code: -1,
        message: '无法获取网易云登录二维码',
        path: NeteaseEndpoints.qrKey,
      );
    }
    return key;
  }

  Future<String> createQrUrl(String key) async =>
      'https://music.163.com/login?codekey=$key';

  Future<NeteaseQrResult> checkQr(String key) async {
    final response = await _client.request(
      NeteaseEndpoints.qrCheck,
      data: {'key': key, 'type': 3},
    );
    final code = JsonUtils.integer(response['code']);
    switch (code) {
      case 800:
        return const NeteaseQrResult(NeteaseQrStatus.expired);
      case 801:
        return const NeteaseQrResult(NeteaseQrStatus.waiting);
      case 802:
        return const NeteaseQrResult(NeteaseQrStatus.scanned);
      case 803:
        await _storeLoginCookie(response);
        if (!isLoggedIn) {
          return const NeteaseQrResult(
            NeteaseQrStatus.failed,
            message: '登录信息解析失败，请重试',
          );
        }
        return const NeteaseQrResult(NeteaseQrStatus.success);
      default:
        return NeteaseQrResult(
          NeteaseQrStatus.failed,
          message: JsonUtils.string(
            response['message'] ?? response['msg'],
            fallback: '二维码登录失败，请重试',
          ),
        );
    }
  }

  // --- Phone login --------------------------------------------------------

  Future<void> sendSmsCode(String phone) async {
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.smsSend,
        data: {
          'ctcode': '86',
          'secrete': 'music_middleuser_pclogin',
          'cellphone': phone,
        },
      ),
      NeteaseEndpoints.smsSend,
    );
  }

  Future<void> loginWithSmsCode({
    required String phone,
    required String code,
  }) async {
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.smsLogin,
        data: {
          'type': '1',
          'https': 'true',
          'phone': phone,
          'countrycode': '86',
          'captcha': code,
          'remember': 'true',
        },
      ),
      NeteaseEndpoints.smsLogin,
    );
    await _storeLoginCookie(response);
    if (!isLoggedIn) {
      throw const BiliApiException(
        code: -1,
        message: '手机号登录失败，请检查验证码',
        path: NeteaseEndpoints.smsLogin,
      );
    }
  }

  // --- Search -------------------------------------------------------------

  Future<PagedResult<MediaTrack>> searchSongs({
    required String keyword,
    int page = 1,
  }) async {
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.search,
        data: {
          's': keyword,
          'type': 1,
          'limit': pageSize,
          'offset': (page - 1) * pageSize,
          'total': true,
        },
      ),
      NeteaseEndpoints.search,
    );
    final result = JsonUtils.map(response['result']);
    final songs = JsonUtils.list(result['songs']);
    final total = JsonUtils.integer(result['songCount']);
    final offset = (page - 1) * pageSize;
    return PagedResult(
      items: [
        for (final song in songs)
          if (JsonUtils.integer(song['id']) > 0) _toTrack(song),
      ],
      page: page,
      hasMore: songs.isNotEmpty && offset + songs.length < total,
      total: total,
    );
  }

  Future<List<String>> suggest(String keyword) async {
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.searchSuggest,
        data: {'s': keyword},
      ),
      NeteaseEndpoints.searchSuggest,
    );
    final result = JsonUtils.map(response['result']);
    final suggestions = <String>[];
    void add(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty || suggestions.contains(trimmed)) return;
      suggestions.add(trimmed);
    }

    for (final item in JsonUtils.list(result['allMatch'])) {
      add(JsonUtils.string(item['keyword']));
    }
    for (final item in JsonUtils.list(result['songs'])) {
      add(JsonUtils.string(item['name']));
    }
    for (final item in JsonUtils.list(result['artists'])) {
      add(JsonUtils.string(item['name']));
    }
    for (final item in JsonUtils.list(result['albums'])) {
      add(JsonUtils.string(item['name']));
    }
    return suggestions.take(10).toList();
  }

  // --- Songs --------------------------------------------------------------

  /// Resolves a playable URL at [quality].
  ///
  /// The API downgrades the request when the level is not available for the
  /// song, so the [NeteaseSongUrl.level] of the result names the quality that
  /// was actually delivered.
  Future<NeteaseSongUrl?> fetchSongUrl(
    int songId, {
    NeteaseQuality quality = NeteaseQuality.exhigh,
  }) async {
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.songUrlV1,
        data: {
          'ids': jsonEncode(['$songId']),
          'level': quality.apiValue,
          'encodeType': 'flac',
        },
      ),
      NeteaseEndpoints.songUrlV1,
    );
    final data = JsonUtils.list(response['data']);
    if (data.isEmpty) return null;
    final first = data.first;
    final url = JsonUtils.string(first['url']);
    if (url.isEmpty) return null;
    return NeteaseSongUrl(
      url: url,
      level: NeteaseQuality.fromApiValue(
        JsonUtils.string(first['level'], fallback: quality.apiValue),
      ),
    );
  }

  /// Levels a song can be played at, from 标准 up to the highest one the
  /// backend reports.
  ///
  /// The highest level is discovered by requesting the top of the ladder: the
  /// API answers with the best level it can deliver, so a single probe is
  /// usually enough. Lower levels are tried only when the request itself fails.
  Future<List<NeteaseQuality>> fetchAvailableQualities(int songId) async {
    for (final quality in NeteaseQuality.values.reversed) {
      try {
        final result = await fetchSongUrl(songId, quality: quality);
        if (result == null) continue;
        final highest = result.level ?? quality;
        return [
          for (final level in NeteaseQuality.values)
            if (level.index <= highest.index) level,
        ];
      } on BiliApiException {
        // Unsupported levels are skipped in favour of the next one down.
      }
    }
    return const [];
  }

  Future<void> likeSong(int songId, {required bool like}) async {
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.like,
        data: {
          'alg': 'itembased',
          'trackId': songId,
          'like': like,
          'time': '3',
        },
        requireLogin: true,
      ),
      NeteaseEndpoints.like,
    );
  }

  // --- Playlists ----------------------------------------------------------

  Future<List<NeteasePlaylist>> fetchUserPlaylists(int userId) async {
    if (!isLoggedIn) return const [];
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.userPlaylist,
        data: {'uid': userId, 'limit': 1000, 'offset': 0, 'includeVideo': true},
        requireLogin: true,
      ),
      NeteaseEndpoints.userPlaylist,
    );
    return [
      for (final item in JsonUtils.list(response['playlist']))
        NeteasePlaylist.fromJson(item),
    ];
  }

  Future<int> createPlaylist(String name) async {
    final response = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistCreate,
        data: {'name': name, 'privacy': '0', 'type': 'NORMAL'},
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistCreate,
    );
    final playlist = JsonUtils.map(response['playlist']);
    final createdId = JsonUtils.integer(
      response['id'] ?? response['playlistId'],
    );
    final id = createdId != 0 ? createdId : JsonUtils.integer(playlist['id']);
    if (id <= 0) {
      throw const BiliApiException(
        code: -1,
        message: '创建歌单失败',
        path: NeteaseEndpoints.playlistCreate,
      );
    }
    return id;
  }

  Future<void> renamePlaylist(int id, String name) async {
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistNameUpdate,
        data: {'id': id, 'name': name},
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistNameUpdate,
    );
  }

  Future<void> deletePlaylist(int id) async {
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistDelete,
        data: {
          'ids': jsonEncode([id]),
        },
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistDelete,
    );
  }

  Future<List<MediaTrack>> fetchPlaylistTracks(int playlistId) async {
    final detail = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistDetail,
        data: {'id': playlistId, 'n': 100000, 's': 8},
      ),
      NeteaseEndpoints.playlistDetail,
    );
    final playlist = JsonUtils.map(detail['playlist']);
    final trackIds = [
      for (final item in JsonUtils.list(playlist['trackIds']))
        JsonUtils.integer(item['id']),
    ].where((id) => id > 0).take(1000).toList();
    if (trackIds.isEmpty) return const [];

    final songs = _client.expectOk(
      await _client.request(
        NeteaseEndpoints.songDetail,
        data: {
          'c': jsonEncode([
            for (final id in trackIds) {'id': id},
          ]),
        },
      ),
      NeteaseEndpoints.songDetail,
    );
    final rawSongs = JsonUtils.list(songs['songs']);
    final byId = {
      for (final song in rawSongs)
        if (JsonUtils.integer(song['id']) > 0)
          JsonUtils.integer(song['id']): song,
    };
    return [
      for (final id in trackIds)
        if (byId[id] case final song?) _toTrack(song),
    ];
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> songIds) async {
    if (songIds.isEmpty) return;
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistTracks,
        data: {
          'op': 'add',
          'pid': playlistId,
          'trackIds': jsonEncode(songIds.map((id) => '$id').toList()),
          'imme': 'true',
        },
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistTracks,
    );
  }

  Future<void> removeTracksFromPlaylist(
    int playlistId,
    List<int> songIds,
  ) async {
    if (songIds.isEmpty) return;
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistTracks,
        data: {
          'op': 'del',
          'pid': playlistId,
          'trackIds': jsonEncode(songIds.map((id) => '$id').toList()),
          'imme': 'true',
        },
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistTracks,
    );
  }

  Future<void> updateTrackOrder(
    int playlistId,
    List<int> orderedSongIds,
  ) async {
    _client.expectOk(
      await _client.request(
        NeteaseEndpoints.playlistTracks,
        data: {
          'op': 'update',
          'pid': playlistId,
          'trackIds': jsonEncode(orderedSongIds),
          'imme': 'true',
        },
        requireLogin: true,
      ),
      NeteaseEndpoints.playlistTracks,
    );
  }

  // --- Helpers ------------------------------------------------------------

  Future<void> _storeLoginCookie(Map<String, dynamic> response) async {
    final raw = response['cookie'];
    if (raw is String) {
      await _client.cookies.mergeHeader(raw);
    } else if (raw is List) {
      await _client.cookies.mergeHeader(
        raw
            .map((item) => item.toString().split(';').first.trim())
            .where((item) => item.contains('='))
            .join('; '),
      );
    }
  }

  MediaTrack _toTrack(Map<String, dynamic> song) {
    final artists = JsonUtils.list(song['ar']).isNotEmpty
        ? JsonUtils.list(song['ar'])
        : JsonUtils.list(song['artists']);
    final album = JsonUtils.map(song['al']).isNotEmpty
        ? JsonUtils.map(song['al'])
        : JsonUtils.map(song['album']);
    final durationMillis = JsonUtils.integer(song['dt']);
    final legacyDuration = JsonUtils.integer(song['duration']);
    final duration = durationMillis > 0
        ? Duration(milliseconds: durationMillis)
        : (legacyDuration > 0
              ? Duration(milliseconds: legacyDuration)
              : Duration.zero);

    return MediaTrack(
      source: TrackSource.netease,
      songId: JsonUtils.integer(song['id']),
      title: JsonUtils.string(song['name'], fallback: '未知歌曲'),
      artist: artists.isEmpty
          ? '未知歌手'
          : artists
                .map((artist) => JsonUtils.string(artist['name']))
                .join(' / '),
      cover: JsonUtils.string(album['picUrl'] ?? song['picUrl']),
      duration: duration,
    );
  }
}
