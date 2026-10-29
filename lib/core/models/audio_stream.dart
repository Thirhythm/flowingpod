import 'json_utils.dart';
import 'package:flowingpod/core/utils/secure_url.dart';

/// A single audio-only stream extracted from a video's DASH manifest.
class AudioStream {
  const AudioStream({
    required this.qualityId,
    required this.url,
    required this.bandwidth,
    required this.mimeType,
    this.backupUrls = const [],
    this.codecs,
  });

  /// DASH audio quality id (see `docs/video/videostream_url.md`).
  final int qualityId;
  final String url;
  final List<String> backupUrls;
  final int bandwidth;
  final String mimeType;
  final String? codecs;

  /// Human readable quality, used in the player UI.
  String get qualityLabel => switch (qualityId) {
    30216 => '64K',
    30232 => '132K',
    30280 => '192K',
    30250 => '杜比全景声',
    30251 => 'Hi-Res 无损',
    _ => '标准',
  };

  factory AudioStream.fromJson(Map<String, dynamic> json) => AudioStream(
    qualityId: JsonUtils.integer(json['id']),
    url: SecureUrl.ensureHttps(
      JsonUtils.string(json['baseUrl'] ?? json['base_url']),
    )!,
    backupUrls: [
      for (final item in JsonUtils.strings(
        json['backupUrl'] ?? json['backup_url'],
      ))
        SecureUrl.ensureHttps(item)!,
    ],
    bandwidth: JsonUtils.integer(json['bandwidth']),
    mimeType: JsonUtils.string(json['mimeType'] ?? json['mime_type'], fallback: 'audio/mp4'),
    codecs: JsonUtils.nullableString(json['codecs']),
  );
}

/// The audio streams available for one video part, ordered best first.
class PlaybackSource {
  const PlaybackSource({required this.streams, this.duration});

  final List<AudioStream> streams;
  final Duration? duration;

  bool get isEmpty => streams.isEmpty;

  AudioStream? get best => streams.isEmpty ? null : streams.first;

  factory PlaybackSource.fromPlayUrl(Map<String, dynamic> json) {
    final dash = JsonUtils.map(json['dash']);
    final streams = <AudioStream>[
      for (final item in JsonUtils.list(dash['audio'])) AudioStream.fromJson(item),
      // Dolby / Hi-Res tracks are higher quality than the standard DASH audio.
      if (JsonUtils.map(dash['flac']).isNotEmpty)
        if (JsonUtils.map(JsonUtils.map(dash['flac'])['audio']).isNotEmpty)
          AudioStream.fromJson(JsonUtils.map(JsonUtils.map(dash['flac'])['audio'])),
    ];

    if (streams.isEmpty) {
      // Legacy `durl` responses expose a single progressive stream.
      final durl = JsonUtils.list(json['durl']);
      if (durl.isNotEmpty) {
        final first = durl.first;
        streams.add(
          AudioStream(
            qualityId: JsonUtils.integer(json['quality']),
            url: SecureUrl.ensureHttps(JsonUtils.string(first['url']))!,
            backupUrls: [
              for (final item in JsonUtils.strings(first['backup_url']))
                SecureUrl.ensureHttps(item)!,
            ],
            bandwidth: 0,
            mimeType: 'audio/mp4',
          ),
        );
      }
    }

    streams.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    final durationMillis = JsonUtils.integer(dash['duration']);
    return PlaybackSource(
      streams: streams.where((stream) => stream.url.isNotEmpty).toList(),
      duration: durationMillis > 0
          ? Duration(milliseconds: durationMillis * 1000)
          : null,
    );
  }
}
