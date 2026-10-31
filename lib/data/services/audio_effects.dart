import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';

/// Sound effects offered by the playback engine.
///
/// Implemented by the audio service. Android 9+ can run the native ten-band
/// dynamics equalizer; other platforms, or devices where the effect cannot be
/// created, keep just_audio's device equalizer. The band layout is only known
/// once the engine has been activated, so [loadCapabilities] may complete late.
abstract interface class AudioEffects {
  /// Band layout and gain range of the platform equalizer.
  Future<EqualizerCapabilities> loadCapabilities();

  /// Bypasses or engages the equalizer.
  ///
  /// Implementations fade the band gains through flat first so that toggling
  /// the effect during playback never produces a click.
  Future<void> setEqualizerEnabled(bool enabled);

  /// Replaces the frequency response.
  ///
  /// The curve is sampled at the engine's own band frequencies, so the same
  /// profile keeps its shape on any band layout. [preampDecibels] is added to
  /// every band afterwards, usually a negative value that leaves headroom for
  /// the boosts of the curve.
  ///
  /// The engine may report its band layout only later, in which case it keeps
  /// the curve and applies it once it is ready. While the equalizer is
  /// engaged, new gains are faded in instead of applied instantly.
  Future<void> setEqualizerCurve(EqualizerCurve curve, {double preampDecibels});

  /// Bypasses or engages the loudness enhancer.
  ///
  /// Like [setEqualizerEnabled], this fades the gain through zero first.
  Future<void> setLoudnessEnabled(bool enabled);

  /// Sets the loudness enhancer target gain in decibels.
  Future<void> setLoudnessGain(double gainDecibels);

  /// Bypasses or engages loudness leveling, which keeps the perceived loudness
  /// of different tracks close by lifting quiet content and limiting peaks.
  Future<void> setVolumeLevelingEnabled(bool enabled);
}
