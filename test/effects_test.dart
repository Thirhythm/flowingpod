import 'dart:async';

import 'package:flowingpod/core/models/audio_effect_settings.dart';
import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_preset.dart';
import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/data/repositories/settings_repository.dart';
import 'package:flowingpod/data/services/audio_effects.dart';
import 'package:flowingpod/features/settings/effects_page.dart';
import 'package:flowingpod/state/effects_controller.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _frequencies = [60.0, 230.0, 910.0, 3600.0, 14000.0];

/// In-memory stand-in for the playback engine's effect pipeline.
///
/// Like the real engine it only knows its band layout once playback starts:
/// [loadCapabilities] stays pending until [ready] is set, and gains requested
/// before that are held back and applied when it turns true.
class _FakeEffects implements AudioEffects {
  _FakeEffects({this.bandCount = 5, this.ready = true});

  int bandCount;

  /// Whether playback has started and the band layout is known.
  bool ready;
  final Completer<EqualizerCapabilities> _layout =
      Completer<EqualizerCapabilities>();

  bool equalizerEnabled = false;
  bool loudnessEnabled = false;
  double loudnessGain = 0;

  /// Gains most recently requested by the app.
  List<double> requestedGains = const [];

  /// Gains that reached the engine bands.
  final Map<int, double> bandGains = {};

  /// Mimics playback starting: the engine reports its band layout and applies
  /// the gains that were requested while it was idle.
  void start() {
    ready = true;
    _layout.complete(_buildCapabilities());
    _flush();
  }

  EqualizerCapabilities _buildCapabilities() => EqualizerCapabilities(
    minDecibels: -15,
    maxDecibels: 15,
    bands: [
      for (var i = 0; i < bandCount; i++)
        EqualizerBand(
          lowerFrequency: 0,
          upperFrequency: 0,
          centerFrequency: i < _frequencies.length
              ? _frequencies[i]
              : 100.0 * (i + 1),
        ),
    ],
  );

  void _flush() {
    final gains = EqualizerPreset.resampleGains(requestedGains, bandCount);
    bandGains.clear();
    for (var i = 0; i < gains.length; i++) {
      bandGains[i] = gains[i];
    }
  }

  @override
  Future<EqualizerCapabilities> loadCapabilities() {
    if (ready) return Future.value(_buildCapabilities());
    return _layout.future;
  }

  @override
  Future<void> setBandGains(List<double> gainsDecibels) async {
    requestedGains = List.of(gainsDecibels);
    if (ready) _flush();
  }

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabled = enabled;
  }

  @override
  Future<void> setLoudnessEnabled(bool enabled) async {
    loudnessEnabled = enabled;
  }

  @override
  Future<void> setLoudnessGain(double gainDecibels) async {
    loudnessGain = gainDecibels;
  }
}

Future<SharedPreferences> _freshPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

ProviderContainer _container(SharedPreferences prefs, _FakeEffects effects) {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      audioEffectsProvider.overrideWithValue(effects),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(SharedPreferences prefs, _FakeEffects effects, Widget home) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioEffectsProvider.overrideWithValue(effects),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  test('preset gains resample to the engine band count', () {
    expect(EqualizerPreset.resampleGains(const [], 3), [0, 0, 0]);
    expect(EqualizerPreset.resampleGains(const [1, 2], 2), [1, 2]);
    expect(EqualizerPreset.resampleGains(const [0, 4], 3), [0, 2, 4]);
    expect(EqualizerPreset.resampleGains(const [0, 4], 1), [0]);
    expect(EqualizerPreset.bassBoost.gainsFor(3), [6, 0, 0]);
    expect(EqualizerPreset.byId('jazz').label, '爵士');
    expect(EqualizerPreset.byId('unknown'), EqualizerPreset.flat);
    expect(EqualizerPreset.byId(EqualizerPreset.customId).isCustom, isTrue);
  });

  test('effect labels read well in Chinese UI', () {
    expect(Formatters.frequency(60), '60Hz');
    expect(Formatters.frequency(3600), '3.6kHz');
    expect(Formatters.frequency(14000), '14kHz');
    expect(Formatters.decibels(0), '+0.0dB');
    expect(Formatters.decibels(-1.5), '-1.5dB');
  });

  test('sound-effect settings round-trip through the repository', () async {
    final prefs = await _freshPrefs();
    final repository = SettingsRepository(prefs);
    final defaults = repository.loadAudioEffects();
    expect(defaults.equalizerEnabled, isFalse);
    expect(defaults.presetId, EqualizerPreset.flatId);
    expect(defaults.loudnessGain, 0);

    await repository.setAudioEffects(
      const AudioEffectSettings(
        equalizerEnabled: true,
        presetId: 'rock',
        bandGains: [3, 2, -1, 1, 3],
        loudnessEnabled: true,
        loudnessGain: 2.5,
      ),
    );

    final restored = repository.loadAudioEffects();
    expect(restored.equalizerEnabled, isTrue);
    expect(restored.presetId, 'rock');
    expect(restored.bandGains, [3, 2, -1, 1, 3]);
    expect(restored.loudnessEnabled, isTrue);
    expect(restored.loudnessGain, 2.5);
  });

  test('a corrupt effects entry falls back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      'settings_audio_effects_v1': 'not json',
    });
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    expect(repository.loadAudioEffects().presetId, EqualizerPreset.flatId);
  });

  test('presets and band edits are mirrored onto the engine', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects();
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    await controller.setEqualizerEnabled(true);
    await controller.selectPreset('bass');
    expect(effects.equalizerEnabled, isTrue);
    expect(effects.bandGains, {0: 6.0, 1: 4.0, 2: 0.0, 3: -1.0, 4: 0.0});

    var stored = SettingsRepository(prefs).loadAudioEffects();
    expect(stored.presetId, 'bass');
    expect(stored.bandGains, [6, 4, 0, -1, 0]);

    await controller.setBandGain(2, 5);
    expect(effects.bandGains[2], 5.0);
    stored = SettingsRepository(prefs).loadAudioEffects();
    expect(stored.presetId, EqualizerPreset.customId);
    expect(stored.bandGains, [6, 4, 5, -1, 0]);

    await controller.setLoudnessEnabled(true);
    await controller.setLoudnessGain(3);
    expect(effects.loudnessEnabled, isTrue);
    expect(effects.loudnessGain, 3);

    await controller.reset();
    expect(effects.loudnessGain, 0);
    expect(effects.bandGains.values, everyElement(0));

    // A fresh container restores the stored profile.
    final reopened = _container(prefs, effects);
    await pumpEventQueue();
    expect(reopened.read(effectsControllerProvider).settings.presetId, 'flat');
  });

  test('stored gains follow the band count the engine reports', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 7);
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    expect(container.read(effectsControllerProvider).engineReady, isTrue);
    await controller.selectPreset('rock');

    final gains = container.read(effectsControllerProvider).bandGains;
    expect(gains, hasLength(7));
    expect(effects.bandGains, hasLength(7));
  });

  test('band gains queue up until the engine reports its layout', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 3, ready: false);
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    // The reference bands are editable before anything has played.
    expect(container.read(effectsControllerProvider).engineReady, isFalse);
    expect(container.read(effectsControllerProvider).bandGains, hasLength(5));

    await controller.setEqualizerEnabled(true);
    await controller.selectPreset('bass');
    expect(effects.equalizerEnabled, isTrue);
    expect(effects.requestedGains, hasLength(5));
    expect(effects.bandGains, isEmpty);

    // Playback starts: the engine reports three bands and receives the gains.
    effects.start();
    await pumpEventQueue();

    expect(container.read(effectsControllerProvider).engineReady, isTrue);
    expect(effects.bandGains, {0: 6.0, 1: 0.0, 2: 0.0});
  });

  testWidgets('the page toggles effects, picks presets and edits bands', (
    tester,
  ) async {
    // Tall enough to hold every section without scrolling, since dragging the
    // band sliders would otherwise steal the gesture.
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.reset);

    final prefs = await _freshPrefs();
    final effects = _FakeEffects();
    await tester.pumpWidget(_wrap(prefs, effects, const EffectsPage()));
    await tester.pumpAndSettle();

    expect(find.text('启用均衡器'), findsOneWidget);
    expect(find.text('低音增强'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text('3.6kHz'), findsOneWidget);
    expect(find.text('230Hz'), findsOneWidget);

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    expect(effects.equalizerEnabled, isTrue);

    await tester.tap(find.text('低音增强'));
    await tester.pumpAndSettle();
    expect(effects.bandGains[0], 6.0);
    expect(SettingsRepository(prefs).loadAudioEffects().presetId, 'bass');

    await tester.tap(find.text('响度增强'));
    await tester.pumpAndSettle();
    expect(effects.loudnessEnabled, isTrue);

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(SettingsRepository(prefs).loadAudioEffects().presetId, 'flat');
  });

  testWidgets('dragging a band slider marks the profile as custom', (
    tester,
  ) async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects();
    await tester.pumpWidget(_wrap(prefs, effects, const EffectsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(effects.bandGains[0], greaterThan(0));
    expect(
      SettingsRepository(prefs).loadAudioEffects().presetId,
      EqualizerPreset.customId,
    );
  });

  testWidgets('the reference bands are editable while the engine is idle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.reset);

    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 3, ready: false);
    await tester.pumpWidget(_wrap(prefs, effects, const EffectsPage()));
    await tester.pumpAndSettle();

    // Five reference bands and the loudness slider, without waiting for the
    // engine to report its layout: the reference bands are shown right away
    // instead of a pending-layout hint.
    expect(find.text('3.6kHz'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(6));

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(effects.bandGains, isEmpty);
    expect(
      SettingsRepository(prefs).loadAudioEffects().presetId,
      EqualizerPreset.customId,
    );

    // Playback starts: the engine swaps in its three bands and the queued
    // gains reach it.
    effects.start();
    await tester.pumpAndSettle();

    expect(find.text('3.6kHz'), findsNothing);
    expect(find.byType(Slider), findsNWidgets(4));
    expect(effects.bandGains[0], greaterThan(0));
  });
}
