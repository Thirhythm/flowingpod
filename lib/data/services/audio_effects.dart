import 'package:flowingpod/core/models/equalizer_capabilities.dart';

/// Sound effects offered by the playback engine.
///
/// Implemented by the audio service on top of just_audio's Android audio
/// effect pipeline. The band layout is only known once the engine has been
/// activated by the first playback, so [loadCapabilities] may complete late.
abstract interface class AudioEffects {
  /// Band layout and gain range of the platform equalizer.
  Future<EqualizerCapabilities> loadCapabilities();

  /// Bypasses or engages the equalizer.
  ///
  /// Implementations fade the band gains through flat first so that toggling
  /// the effect during playback never produces a click.
  Future<void> setEqualizerEnabled(bool enabled);

  /// Sets every band gain in decibels, low frequency first.
  ///
  /// The engine may report its band layout only later, in which case it keeps
  /// the gains and applies them (resampled to its bands) once it is ready.
  /// While the equalizer is engaged, new gains are faded in instead of applied
  /// instantly.
  Future<void> setBandGains(List<double> gainsDecibels);

  /// Bypasses or engages the loudness enhancer.
  ///
  /// Like [setEqualizerEnabled], this fades the gain through zero first.
  Future<void> setLoudnessEnabled(bool enabled);

  /// Sets the loudness enhancer target gain in decibels.
  Future<void> setLoudnessGain(double gainDecibels);
}
