import 'dart:async';

import 'package:flowingpod/core/models/audio_effect_settings.dart';
import 'package:flowingpod/core/models/equalizer_capabilities.dart';
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

  /// Stored band gains matched to [bandLayout] and its gain range.
  List<double> get bandGains {
    final capabilities = this.capabilities;
    final gains = EqualizerPreset.resampleGains(
      settings.bandGains,
      bandLayout.bands.length,
    );
    if (capabilities == null) return gains;
    return [
      for (final gain in gains)
        gain
            .clamp(capabilities.minDecibels, capabilities.maxDecibels)
            .toDouble(),
    ];
  }
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

  Future<void> setLoudnessEnabled(bool enabled) =>
      _update(state.settings.copyWith(loudnessEnabled: enabled));

  Future<void> setLoudnessGain(double gain) =>
      _update(state.settings.copyWith(loudnessGain: gain));

  /// Switches to a named profile and applies its gains.
  Future<void> selectPreset(String presetId) {
    final preset = EqualizerPreset.byId(presetId);
    return _update(
      state.settings.copyWith(
        presetId: preset.id,
        bandGains: preset.gainsFor(state.bandLayout.bands.length),
      ),
    );
  }

  /// Edits one band by hand, turning the profile into `自定义`.
  Future<void> setBandGain(int index, double gain) {
    final gains = state.bandGains;
    if (index < 0 || index >= gains.length) return Future.value();
    final updated = List.of(gains);
    updated[index] = gain;
    return _update(
      state.settings.copyWith(
        presetId: EqualizerPreset.customId,
        bandGains: updated,
      ),
    );
  }

  /// Restores the flat profile and the neutral loudness gain.
  Future<void> reset() => _update(
    state.settings.copyWith(
      presetId: EqualizerPreset.flatId,
      bandGains: EqualizerPreset.flat.gainsFor(state.bandLayout.bands.length),
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
      await effects.setEqualizerEnabled(settings.equalizerEnabled);
      await effects.setLoudnessEnabled(settings.loudnessEnabled);
      await effects.setLoudnessGain(settings.loudnessGain);
      await effects.setBandGains(state.bandGains);
    } catch (_) {
      // The engine rejects effect calls on platforms without effect support.
    }
  }

  /// Waits for the engine to report its band layout, then applies the gains.
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
