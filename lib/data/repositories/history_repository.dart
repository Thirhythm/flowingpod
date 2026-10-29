import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/bili_endpoints.dart';
import 'package:flowingpod/core/models/history_entry.dart';
import 'package:flowingpod/core/models/json_utils.dart';

/// Infinite-scroll cursor for the history list.
class HistoryCursor {
  const HistoryCursor({this.max = 0, this.viewAt = 0, this.business = ''});

  final int max;
  final int viewAt;
  final String business;

  bool get isStart => max == 0 && viewAt == 0 && business.isEmpty;
}

/// One page of watch history together with the cursor for the next page.
class HistoryPage {
  const HistoryPage({
    required this.entries,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<HistoryEntry> entries;
  final HistoryCursor nextCursor;
  final bool hasMore;
}

/// Reads and manages the signed-in user's watch history.
class HistoryRepository {
  HistoryRepository(this._client);

  final BiliClient _client;

  static const int pageSize = 20;

  Future<HistoryPage> fetchHistory({
    HistoryCursor cursor = const HistoryCursor(),
    int size = pageSize,
  }) async {
    final response = await _client.getJson(
      BiliEndpoints.historyCursor,
      requireLogin: true,
      query: {
        'ps': size,
        'max': cursor.max,
        'view_at': cursor.viewAt,
        'business': cursor.business,
        'type': 'all',
      },
    );
    final data = JsonUtils.map(response['data']);
    final rawList = JsonUtils.list(data['list']);
    final entries = <HistoryEntry>[];
    for (final item in rawList) {
      final entry = HistoryEntry.fromJson(item);
      if (entry.isValid) entries.add(entry);
    }

    final rawCursor = JsonUtils.map(data['cursor']);
    final nextCursor = HistoryCursor(
      max: JsonUtils.integer(rawCursor['max']),
      viewAt: JsonUtils.integer(rawCursor['view_at']),
      business: JsonUtils.string(rawCursor['business']),
    );

    return HistoryPage(
      entries: entries,
      nextCursor: nextCursor,
      hasMore: rawList.length >= size && !nextCursor.isStart,
    );
  }

  /// Deletes a single entry. [HistoryEntry.deleteKid] must be available.
  Future<void> deleteEntry(HistoryEntry entry) async {
    final kid = entry.deleteKid;
    if (kid == null) {
      throw const BiliApiException(code: -400, message: '该记录无法删除');
    }
    await _client.postForm(BiliEndpoints.historyDelete, {
      'kid': kid,
      'csrf': _csrf(),
    });
  }

  /// Removes the whole watch history.
  Future<void> clearHistory() =>
      _client.postForm(BiliEndpoints.historyClear, {'csrf': _csrf()});

  String _csrf() {
    final token = _client.cookies.csrfToken;
    if (token == null || token.isEmpty) {
      throw const BiliApiException(code: -101, message: '登录状态已失效，请重新登录');
    }
    return token;
  }
}
