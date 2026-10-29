import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/netease_client.dart';
import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flowingpod/data/repositories/fav_repository.dart';
import 'package:flowingpod/data/repositories/history_repository.dart';
import 'package:flowingpod/data/repositories/local_history_repository.dart';
import 'package:flowingpod/data/repositories/local_playlist_repository.dart';
import 'package:flowingpod/data/repositories/local_recent_playlists_repository.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/data/repositories/search_repository.dart';
import 'package:flowingpod/data/repositories/settings_repository.dart';
import 'package:flowingpod/data/repositories/video_repository.dart';
import 'package:flowingpod/data/services/audio_effects.dart';
import 'package:flowingpod/data/services/player_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three providers below are overridden in `main()` once the asynchronous
/// bootstrap (cookie jar, audio service) has finished.

final Provider<BiliClient> biliClientProvider = Provider<BiliClient>(
  (ref) => throw StateError('biliClientProvider must be overridden in main()'),
);

/// NetEase API client; created in `main()` after the encrypted cookie jar has
/// been loaded, so the audio service and the UI share the same session.
final Provider<NeteaseClient> neteaseClientProvider = Provider<NeteaseClient>(
  (ref) => throw StateError('neteaseClientProvider must be overridden in main()'),
);

final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (ref) => throw StateError(
        'sharedPreferencesProvider must be overridden in main()',
      ),
    );

final Provider<BiliAudioService> audioServiceProvider =
    Provider<BiliAudioService>(
      (ref) => throw StateError('audioServiceProvider must be overridden'),
    );

/// Sound-effect surface of the audio service, split out so tests can fake the
/// engine without constructing a real [BiliAudioService].
final Provider<AudioEffects> audioEffectsProvider = Provider<AudioEffects>(
  (ref) => ref.watch(audioServiceProvider),
);

// --- Repositories ---------------------------------------------------------

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (ref) => AuthRepository(ref.watch(biliClientProvider)),
    );

final Provider<VideoRepository> videoRepositoryProvider =
    Provider<VideoRepository>(
      (ref) => VideoRepository(ref.watch(biliClientProvider)),
    );

final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>(
      (ref) => SearchRepository(ref.watch(biliClientProvider)),
    );

final Provider<FavRepository> favRepositoryProvider = Provider<FavRepository>(
  (ref) => FavRepository(ref.watch(biliClientProvider)),
);

final Provider<HistoryRepository> historyRepositoryProvider =
    Provider<HistoryRepository>(
      (ref) => HistoryRepository(ref.watch(biliClientProvider)),
    );

final Provider<NeteaseRepository> neteaseRepositoryProvider =
    Provider<NeteaseRepository>(
      (ref) => NeteaseRepository(ref.watch(neteaseClientProvider)),
    );

/// On-device play history, used while no Bilibili session is active.
final Provider<LocalHistoryRepository> localHistoryRepositoryProvider =
    Provider<LocalHistoryRepository>(
      (ref) => LocalHistoryRepository(ref.watch(sharedPreferencesProvider)),
    );

/// On-device record of the playlists played from.
final Provider<LocalRecentPlaylistsRepository>
localRecentPlaylistsRepositoryProvider =
    Provider<LocalRecentPlaylistsRepository>(
      (ref) => LocalRecentPlaylistsRepository(
        ref.watch(sharedPreferencesProvider),
      ),
    );

/// On-device playlists, including the built-in 我喜欢的音乐.
final Provider<LocalPlaylistRepository> localPlaylistRepositoryProvider =
    Provider<LocalPlaylistRepository>(
      (ref) => LocalPlaylistRepository(ref.watch(sharedPreferencesProvider)),
    );

/// On-device app preferences.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
      (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
    );
