import 'dart:async';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/core/models/play_mode.dart';
import 'package:flowingpod/core/models/player_state.dart';
import 'package:flowingpod/data/services/player_service.dart';
import 'package:flowingpod/state/auth_controller.dart';
import 'package:flowingpod/state/library_controllers.dart';
import 'package:flowingpod/state/local_history_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mirror of the audio service state, consumed by the UI.
final NotifierProvider<PlayerController, PlayerState> playerStateProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

/// Playback position, updated several times per second.
final StreamProvider<Duration> playbackPositionProvider =
    StreamProvider<Duration>((ref) {
      return ref.watch(audioServiceProvider).positionStream;
    });

/// Commands exposed to the widgets.
class PlayerController extends Notifier<PlayerState> {
  String? _lastRecordedTrackId;

  @override
  PlayerState build() {
    final service = ref.watch(audioServiceProvider);
    final subscription = service.stateStream.listen(_onServiceState);
    ref.onDispose(subscription.cancel);

    final initial = service.state;
    _lastRecordedTrackId = initial.currentTrack?.id;
    return initial;
  }

  BiliAudioService get _service => ref.read(audioServiceProvider);

  void _onServiceState(PlayerState next) {
    if (!ref.mounted) return;
    state = next;
    final track = next.currentTrack;
    // Only fully identified tracks are recorded; a placeholder would sit next
    // to the real part as a duplicate row.
    if (track == null ||
        !track.isResolved ||
        track.id == _lastRecordedTrackId) {
      return;
    }
    _lastRecordedTrackId = track.id;
    unawaited(_recordHistory(track));
  }

  /// Stores the played [track] in the on-device history, which is what the
  /// home page's 最近播放 is built from, and reports it to the Bilibili account
  /// as well when signed in.
  ///
  /// The local record is written in both cases on purpose: the home page always
  /// shows the tracks played in this app, signed in or not.
  Future<void> _recordHistory(MediaTrack track) async {
    final signedIn = ref.read(authControllerProvider).isLoggedIn;
    final localHistory = ref.read(localHistoryProvider.notifier);
    // Only Bilibili videos belong to the Bilibili watch history.
    final cloudHistory = signedIn && !track.isNetease
        ? ref.read(historyRepositoryProvider)
        : null;

    await localHistory.record(track);
    if (cloudHistory == null) return;

    try {
      await cloudHistory.reportProgress(track: track);
      if (ref.mounted) ref.invalidate(historyProvider);
    } on BiliApiException {
      // Reporting to the cloud is best-effort: the local record above already
      // captured the playback.
    }
  }

  /// Plays an explicit list, e.g. every item of a favourite folder.
  ///
  /// The queue is handed over right away and the audio keeps loading
  /// afterwards.
  Future<void> playTracks(List<MediaTrack> tracks, {int startIndex = 0}) async {
    unawaited(_service.setQueue(tracks, startIndex: startIndex));
  }

  /// Plays one track directly after the current entry.
  ///
  /// The track is inserted behind the one playing now and starts right away; a
  /// track the queue already holds is moved there instead of being added twice.
  /// With an empty queue it simply becomes the queue. Bilibili entries that
  /// still lack a part id, such as search results, are expanded into the video's
  /// parts by the player itself.
  Future<void> playTrack(MediaTrack track) => _service.playNext(track);

  Future<void> togglePlay() =>
      state.playing ? _service.pause() : _service.play();

  Future<void> play() => _service.play();

  Future<void> pause() => _service.pause();

  /// Queues [track] right after the current one.
  ///
  /// Returns `false` when [track] is the entry playing already, which has no
  /// next to be moved ahead of.
  Future<bool> addToNext(MediaTrack track) => _service.insertNext(track);

  Future<void> next() => _service.next();

  Future<void> previous() => _service.previous();

  Future<void> seek(Duration position) => _service.seek(position);

  Future<void> playAt(int index) => _service.playAt(index);

  Future<void> setMode(PlayMode mode) => _service.setPlayMode(mode);

  Future<void> cycleMode() => _service.cyclePlayMode();

  Future<void> removeAt(int index) => _service.removeFromQueue(index);

  Future<void> clear() => _service.clearQueue();
}
