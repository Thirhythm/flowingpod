import 'dart:async';

import 'package:flowingpod/core/models/audio_effect_settings.dart';
import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';
import 'package:flowingpod/core/models/equalizer_preset.dart';
import 'package:flowingpod/data/services/audio_effects.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stored sound-effect preferences plus what the engine currently offers.
class EffectsState {
  const EffectsState({required this.settings, this.capabilities});

  final AudioEffectSettings settings;

  /// Band layout of the engine, `null` while the playback engine is idle.
  final EqualizerCapabilities? capabilities;

  /// Whether the engine has reported its band layout.
  bool get engineReady => capabilities != null;

  /// Bands to edit against: the engine's own once known, the reference
  /// five-band layout before that, so the sliders are always usable.
  EqualizerCapabilities get bandLayout =>
      capabilities ?? EqualizerCapabilities.reference;

  /// The stored curve sampled at the centres of [bandLayout], inside the gain
  /// range the engine accepts.
  List<double> get bandGains {
    final gains = settings.curve.sampleAt(bandLayout.centerFrequencies);
    final capabilities = this.capabilities;
    if (capabilities == null) return gains;
    return [
      for (final gain in gains)
        gain
            .clamp(capabilities.minDecibels, capabilities.maxDecibels)
            .toDouble(),
    ];
  }

  /// Attenuation keeping the boosted part of the curve from clipping.
  double get preampDecibels => settings.preampDecibels;
}

/// Equalizer and loudness enhancer preferences, mirrored onto the engine.
final NotifierProvider<EffectsController, EffectsState>
effectsControllerProvider = NotifierProvider<EffectsController, EffectsState>(
  EffectsController.new,
);

class EffectsController extends Notifier<EffectsState> {
  @override
  EffectsState build() {
    final settings = ref.watch(settingsRepositoryProvider).loadAudioEffects();
    final effects = ref.watch(audioEffectsProvider);
    unawaited(_syncEngine(effects, settings));
    unawaited(_loadCapabilities(effects));
    return EffectsState(settings: settings);
  }

  /// Whether the band sliders can be shown.
  bool get engineReady => state.engineReady;

  Future<void> setEqualizerEnabled(bool enabled) =>
      _update(state.settings.copyWith(equalizerEnabled: enabled));

  Future<void> setHeadroomEnabled(bool enabled) =>
      _update(state.settings.copyWith(headroomEnabled: enabled));

  Future<void> setLoudnessEnabled(bool enabled) =>
      _update(state.settings.copyWith(loudnessEnabled: enabled));

  Future<void> setLoudnessGain(double gain) =>
      _update(state.settings.copyWith(loudnessGain: gain));

  /// Switches to a named profile and applies its curve.
  Future<void> selectPreset(String presetId) {
    final preset = EqualizerPreset.byId(presetId);
    return _update(
      state.settings.copyWith(presetId: preset.id, curve: preset.curve),
    );
  }

  /// Edits one band by hand, turning the profile into `自定义`.
  ///
  /// The edit is stored as a control point at the band frequency, so the rest
  /// of the curve — and therefore the other bands — keeps its response.
  Future<void> setBandGain(int index, double gain) {
    final bands = state.bandLayout.bands;
    if (index < 0 || index >= bands.length) return Future.value();
    var curve = state.settings.curve;
    if (curve.points.length < 2) {
      // Pin the current response to the visible bands first; a lone control
      // point would otherwise move every other band with the edited one.
      final shown = state.bandGains;
      curve = EqualizerCurve([
        for (var i = 0; i < bands.length; i++)
          EqualizerPoint(bands[i].centerFrequency, shown[i]),
      ]);
    }
    return _update(
      state.settings.copyWith(
        presetId: EqualizerPreset.customId,
        curve: curve.withGainAt(bands[index].centerFrequency, gain),
      ),
    );
  }

  /// Restores the flat profile, the neutral loudness gain and headroom on.
  Future<void> reset() => _update(
    state.settings.copyWith(
      presetId: EqualizerPreset.flatId,
      curve: EqualizerPreset.flat.curve,
      headroomEnabled: true,
      loudnessGain: 0.0,
    ),
  );

  Future<void> _update(AudioEffectSettings settings) async {
    state = EffectsState(settings: settings, capabilities: state.capabilities);
    await ref.read(settingsRepositoryProvider).setAudioEffects(settings);
    if (!ref.mounted) return;
    await _syncEngine(ref.read(audioEffectsProvider), settings);
  }

  /// Pushes the stored preferences onto the audio engine. The engine keeps the
  /// values while it is idle and applies them once it reports its band layout.
  Future<void> _syncEngine(
    AudioEffects effects,
    AudioEffectSettings settings,
  ) async {
    try {
      // The curve goes first so engaging the equalizer fades in the requested
      // response instead of the previous one.
      await effects.setEqualizerCurve(
        settings.curve,
        preampDecibels: settings.preampDecibels,
      );
      await effects.setEqualizerEnabled(settings.equalizerEnabled);
      await effects.setLoudnessEnabled(settings.loudnessEnabled);
      await effects.setLoudnessGain(settings.loudnessGain);
    } catch (_) {
      // The engine rejects effect calls on platforms without effect support.
    }
  }

  /// Waits for the engine to report its band layout, then applies the curve.
  Future<void> _loadCapabilities(AudioEffects effects) async {
    EqualizerCapabilities capabilities;
    try {
      capabilities = await effects.loadCapabilities();
    } catch (_) {
      // No layout available; the reference bands stay editable.
      return;
    }
    if (!ref.mounted) return;
    state = EffectsState(settings: state.settings, capabilities: capabilities);
    await _syncEngine(effects, state.settings);
  }
}
