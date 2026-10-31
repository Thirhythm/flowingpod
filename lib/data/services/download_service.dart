import 'dart:io';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/models/audio_stream.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/netease_quality.dart';
import 'package:flowingpod/core/utils/storage_paths.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/data/repositories/video_repository.dart';
import 'package:flowingpod/data/services/download_bridge.dart';

/// Raised when a track cannot be downloaded; [message] is user facing.
class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A download handed to the Android service; progress is shown by a
/// notification, so no further work happens on the Dart side.
class QueuedDownload {
  const QueuedDownload({required this.file, required this.qualityLabel});

  final File file;
  final String qualityLabel;
}

/// Resolves a playable stream and hands it to the background downloader.
class DownloadService {
  DownloadService(this._videoRepository, this._neteaseRepository);

  static const Map<String, String> _biliHeaders = {
    'User-Agent': BiliClient.userAgent,
    'Referer': 'https://www.bilibili.com/',
  };

  static const Map<String, String> _neteaseHeaders = {
    'User-Agent': BiliClient.userAgent,
    'Referer': 'https://music.163.com/',
  };

  static const Set<String> _knownExtensions = {
    'aac',
    'flac',
    'm4a',
    'mp3',
    'ogg',
    'wav',
  };

  final VideoRepository _videoRepository;
  final NeteaseRepository _neteaseRepository;

  /// Resolves [track] and starts downloading it into [directory], defaulting to
  /// the shared Music folder.
  ///
  /// Bilibili tracks always use the best available stream. NetEase tracks use
  /// [quality], or 极高 when the caller has no preference.
  Future<QueuedDownload> enqueue(
    MediaTrack track, {
    NeteaseQuality? quality,
    String? directory,
  }) async {
    final _ResolvedDownload resolved;
    try {
      resolved = await _resolve(track, quality);
    } on BiliApiException catch (error) {
      throw DownloadException(error.message);
    }

    final folder = Directory(
      (directory == null || directory.trim().isEmpty)
          ? StoragePaths.defaultMusicDirectory
          : directory,
    );
    try {
      await folder.create(recursive: true);
    } on FileSystemException {
      throw const DownloadException('无法创建下载文件夹，请检查存储权限或修改下载路径');
    }

    final file = await _availableFile(folder, track, resolved.extension);
    final started = await DownloadBridge.enqueueDownload(
      urls: [resolved.url, ...resolved.backupUrls],
      headers: resolved.headers,
      filePath: file.path,
      title: track.displayTitle,
      subtitle: [track.artist, resolved.qualityLabel]
          .where((part) => part.trim().isNotEmpty)
          .join(' · '),
    );
    if (!started) {
      throw const DownloadException('无法启动后台下载，请稍后重试');
    }
    return QueuedDownload(file: file, qualityLabel: resolved.qualityLabel);
  }

  Future<_ResolvedDownload> _resolve(
    MediaTrack track,
    NeteaseQuality? quality,
  ) async {
    if (track.isNetease) {
      if (track.songId <= 0) {
        throw const DownloadException('无法识别该网易云歌曲');
      }
      final requested = quality ?? NeteaseQuality.exhigh;
      final result = await _neteaseRepository.fetchSongUrl(
        track.songId,
        quality: requested,
      );
      if (result == null) {
        throw const DownloadException('无法获取下载链接，该歌曲可能受版权限制或需要登录');
      }
      final served = result.level ?? requested;
      return _ResolvedDownload(
        url: result.url,
        headers: _neteaseHeaders,
        qualityLabel: served.label,
        extension: _extensionFromUrl(
          result.url,
          fallback: served.index >= NeteaseQuality.lossless.index
              ? 'flac'
              : 'mp3',
        ),
      );
    }

    if (track.bvid.isEmpty) {
      throw const DownloadException('无法识别该哔哩哔哩视频');
    }
    final source = await _videoRepository.fetchPlaybackSource(
      bvid: track.bvid,
      cid: await _bilibiliCid(track),
    );
    final stream = source.best;
    if (stream == null) {
      throw const DownloadException('该视频没有可下载的音轨');
    }
    return _ResolvedDownload(
      url: stream.url,
      backupUrls: stream.backupUrls,
      headers: _biliHeaders,
      qualityLabel: stream.qualityLabel,
      extension: _extensionForStream(stream),
    );
  }

  /// Queue entries normally carry a cid; search results only have a bvid.
  Future<int> _bilibiliCid(MediaTrack track) async {
    if (track.cid > 0) return track.cid;
    final detail = await _videoRepository.fetchDetail(bvid: track.bvid);
    for (final part in detail.parts) {
      if (part.page == track.page) return part.cid;
    }
    return detail.parts.first.cid;
  }

  String _extensionForStream(AudioStream stream) {
    final mime = stream.mimeType.toLowerCase();
    final codecs = (stream.codecs ?? '').toLowerCase();
    if (mime.contains('flac') || codecs.contains('flac')) return 'flac';
    return _extensionFromUrl(stream.url, fallback: 'm4a');
  }

  String _extensionFromUrl(String url, {required String fallback}) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0) return fallback;
    final extension = path.substring(dot + 1);
    return _knownExtensions.contains(extension) ? extension : fallback;
  }

  Future<File> _availableFile(
    Directory folder,
    MediaTrack track,
    String extension,
  ) async {
    final base = _sanitize(
      [track.artist, track.title]
          .where((part) => part.trim().isNotEmpty)
          .join(' - '),
    );
    final stem = base.isEmpty ? '未知歌曲' : base;
    var candidate = File(
      '${folder.path}${Platform.pathSeparator}$stem.$extension',
    );
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${folder.path}${Platform.pathSeparator}$stem ($index).$extension',
      );
      index++;
    }
    return candidate;
  }

  String _sanitize(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    return cleaned.length <= 120 ? cleaned : cleaned.substring(0, 120);
  }
}

class _ResolvedDownload {
  const _ResolvedDownload({
    required this.url,
    required this.headers,
    required this.qualityLabel,
    required this.extension,
    this.backupUrls = const [],
  });

  final String url;
  final List<String> backupUrls;
  final Map<String, String> headers;
  final String qualityLabel;
  final String extension;
}
