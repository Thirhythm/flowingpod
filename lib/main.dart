import 'package:audio_service/audio_service.dart';
import 'package:flowingpod/app.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/netease_client.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/data/repositories/video_repository.dart';
import 'package:flowingpod/data/services/player_service.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Covers decode at their rendered size, so the 100 MB default bitmap cache
  // is far more than this player (thumbnails plus one artwork) ever needs.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 32 << 20
    ..maximumSize = 300;

  // Restores the cookie jar and prepares the anonymous device identity.
  final client = await BiliClient.create();
  final preferences = await SharedPreferences.getInstance();

  // Shared by the audio service and the UI so a NetEase login is picked up by
  // playback without restarting the app.
  final neteaseClient = await NeteaseClient.create(preferences);
  final neteaseRepository = NeteaseRepository(neteaseClient);

  // audio_service must own the player so playback survives in the background
  // and the system notification can control it.
  final audioService = await AudioService.init<BiliAudioService>(
    builder: () => BiliAudioService(
      videoRepository: VideoRepository(client),
      neteaseRepository: neteaseRepository,
      preferences: preferences,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'thirhythm.flowingpod.audio',
      androidNotificationChannelName: 'FlowingPod 音频播放',
      androidNotificationChannelDescription: '显示正在播放的音频并提供播放控制',
      androidNotificationOngoing: false,
      // Keeping the service in the foreground while paused avoids
      // ForegroundServiceStartNotAllowedException on Android 12+.
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        biliClientProvider.overrideWithValue(client),
        neteaseClientProvider.overrideWithValue(neteaseClient),
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioServiceProvider.overrideWithValue(audioService),
      ],
      child: const FlowingPodApp(),
    ),
  );
}
