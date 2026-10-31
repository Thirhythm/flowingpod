import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flowingpod/core/models/audio_effect_settings.dart';
import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';
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

const _referenceFrequencies = [60.0, 230.0, 910.0, 3600.0, 14000.0];

/// In-memory stand-in for the playback engine's effect pipeline.
///
/// It samples the curve at its own band frequencies like the real engine does,
/// and like the real engine it only knows its layout once playback starts:
/// [loadCapabilities] stays pending until [ready] is set.
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
  bool volumeLevelingEnabled = false;

  /// Response most recently requested by the app.
  EqualizerCurve curve = EqualizerCurve.flat;
  double preampDecibels = 0;

  /// Gains that reached the engine bands.
  final Map<int, double> bandGains = {};

  /// Mimics playback starting: the engine reports its band layout and applies
  /// the curve that was requested while it was idle.
  void start() {
    ready = true;
    _layout.complete(_buildCapabilities());
    _flush();
  }

  /// The five reference bands, or an octave spread over 31 Hz – 16 kHz.
  double _centerFrequency(int index) {
    if (bandCount == _referenceFrequencies.length) {
      return _referenceFrequencies[index];
    }
    if (bandCount == 1) return 1000;
    const low = 31.0;
    const high = 16000.0;
    return low * math.pow(high / low, index / (bandCount - 1));
  }

  EqualizerCapabilities _buildCapabilities() => EqualizerCapabilities(
    minDecibels: -15,
    maxDecibels: 15,
    bands: [
      for (var i = 0; i < bandCount; i++)
        EqualizerBand(
          lowerFrequency: i == 0 ? 20 : _centerFrequency(i) - 1,
          upperFrequency: i == bandCount - 1 ? 20000 : _centerFrequency(i + 1),
          centerFrequency: _centerFrequency(i),
        ),
    ],
  );

  void _flush() {
    bandGains.clear();
    if (!ready) return;
    for (var i = 0; i < bandCount; i++) {
      bandGains[i] = (curve.gainAt(_centerFrequency(i)) + preampDecibels)
          .clamp(-15.0, 15.0)
          .toDouble();
    }
  }

  @override
  Future<EqualizerCapabilities> loadCapabilities() {
    if (ready) return Future.value(_buildCapabilities());
    return _layout.future;
  }

  @override
  Future<void> setEqualizerCurve(
    EqualizerCurve curve, {
    double preampDecibels = 0,
  }) async {
    this.curve = curve;
    this.preampDecibels = preampDecibels;
    _flush();
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

  @override
  Future<void> setVolumeLevelingEnabled(bool enabled) async {
    volumeLevelingEnabled = enabled;
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
  test('curves interpolate on a logarithmic frequency axis', () {
    const curve = EqualizerCurve([
      EqualizerPoint(100, 0),
      EqualizerPoint(1600, 6),
    ]);

    expect(curve.gainAt(100), 0);
    expect(curve.gainAt(1600), 6);
    // Below the first and above the last point the nearest gain is held.
    expect(curve.gainAt(20), 0);
    expect(curve.gainAt(20000), 6);
    // 400 Hz is the geometric middle between 100 Hz and 1600 Hz.
    expect(curve.gainAt(400), closeTo(3, 0.01));
    expect(curve.sampleAt(const [100, 1600]), [0, 6]);
    expect(curve.peakGain, 6);
  });

  test('editing a point replaces the one at the same frequency', () {
    final curve = const EqualizerCurve([
      EqualizerPoint(100, 1),
      EqualizerPoint(1000, 2),
    ]).withGainAt(1000, -3).withGainAt(400, 4);

    expect(curve.points, hasLength(3));
    expect(curve.gainAt(1000), -3);
    expect(curve.gainAt(400), 4);
    expect(curve.points.map((p) => p.frequency), [100, 400, 1000]);
  });

  test('preset curves are sampled at the band frequencies', () {
    final bass = EqualizerPreset.bassBoost.curve;
    expect(bass.gainAt(31), 7);
    expect(bass.gainAt(62), 6);
    expect(bass.gainAt(1000), 0);
    expect(bass.gainAt(20000), 0);

    // Devices with the standard ten bands get the table as written.
    expect(
      EqualizerPreset.bassBoost.gainsFor(EqualizerPreset.anchorFrequencies),
      [7, 6, 5, 3, 1, 0, 0, 0, 0, 0],
    );

    // The five reference bands are sampled in between the anchors instead of
    // stretching the table by band index.
    final five = EqualizerPreset.bassBoost.gainsFor(
      EqualizerCapabilities.reference.centerFrequencies,
    );
    expect(five, hasLength(5));
    expect(five[0], closeTo(6.05, 0.05)); // 60 Hz between 31 Hz and 62 Hz
    expect(five[1], closeTo(3.24, 0.05)); // 230 Hz between 125 Hz and 250 Hz
    expect(five[2], closeTo(0.14, 0.05)); // 910 Hz between 500 Hz and 1 kHz
    expect(five[3], 0);
    expect(five[4], 0);
  });

  test('the native layout offers ten fixed bands', () {
    const capabilities = EqualizerCapabilities.nativeTenBand;
    expect(capabilities.bands, hasLength(10));
    expect(capabilities.bands.first.centerFrequency, 31);
    expect(capabilities.bands.last.centerFrequency, 16000);
    expect(capabilities.minDecibels, -12);
    expect(capabilities.maxDecibels, 12);
  });

  test('a ten-band engine receives the preset on all ten bands', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 10);
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    await controller.setHeadroomEnabled(false);
    await controller.selectPreset('bass');

    expect(effects.bandGains, hasLength(10));
    expect(effects.bandGains[0], closeTo(7, 0.05));
    expect(effects.bandGains[9], closeTo(0, 0.05));
    expect(container.read(effectsControllerProvider).bandGains, hasLength(10));
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
    expect(defaults.curve, EqualizerCurve.flat);
    expect(defaults.headroomEnabled, isTrue);
    expect(defaults.loudnessGain, 0);

    await repository.setAudioEffects(
      AudioEffectSettings(
        equalizerEnabled: true,
        presetId: 'rock',
        curve: EqualizerPreset.rock.curve,
        headroomEnabled: false,
        loudnessEnabled: true,
        loudnessGain: 2.5,
      ),
    );

    final restored = repository.loadAudioEffects();
    expect(restored.equalizerEnabled, isTrue);
    expect(restored.presetId, 'rock');
    expect(restored.curve, EqualizerPreset.rock.curve);
    expect(restored.headroomEnabled, isFalse);
    expect(restored.loudnessEnabled, isTrue);
    expect(restored.loudnessGain, 2.5);
  });

  test('legacy band gains are placed on the reference frequencies', () async {
    SharedPreferences.setMockInitialValues({
      'settings_audio_effects_v1': jsonEncode({
        'equalizerEnabled': true,
        'presetId': 'rock',
        'bandGains': [3, 2, -1, 1, 3],
        'loudnessEnabled': false,
        'loudnessGain': 0,
      }),
    });
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );

    final settings = repository.loadAudioEffects();
    expect(settings.headroomEnabled, isTrue);
    expect(settings.curve.gainAt(60), 3);
    expect(settings.curve.gainAt(230), 2);
    expect(settings.curve.gainAt(910), -1);
    expect(settings.curve.gainAt(14000), 3);
  });

  test('a corrupt effects entry falls back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      'settings_audio_effects_v1': 'not json',
    });
    final repository = SettingsRepository(
      await SharedPreferences.getInstance(),
    );
    expect(repository.loadAudioEffects().presetId, EqualizerPreset.flatId);
    expect(repository.loadAudioEffects().curve, EqualizerCurve.flat);
  });

  test('presets and band edits are mirrored onto the engine', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects();
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    // Headroom is tested on its own; keep it out of the curve assertions.
    await controller.setHeadroomEnabled(false);
    await controller.setEqualizerEnabled(true);
    await controller.selectPreset('bass');
    expect(effects.equalizerEnabled, isTrue);
    expect(effects.curve, EqualizerPreset.bassBoost.curve);
    expect(effects.bandGains[0], closeTo(6.05, 0.05));
    expect(effects.bandGains[1], closeTo(3.24, 0.05));
    expect(effects.bandGains[4], closeTo(0, 0.01));

    var stored = SettingsRepository(prefs).loadAudioEffects();
    expect(stored.presetId, 'bass');
    expect(stored.curve, EqualizerPreset.bassBoost.curve);

    await controller.setBandGain(2, 5);
    expect(effects.bandGains[2], closeTo(5, 0.01));
    stored = SettingsRepository(prefs).loadAudioEffects();
    expect(stored.presetId, EqualizerPreset.customId);
    expect(stored.curve.gainAt(910), closeTo(5, 0.01));
    // The untouched bands keep the response they had.
    expect(stored.curve.gainAt(60), closeTo(6.05, 0.05));
    expect(stored.curve.gainAt(14000), closeTo(0, 0.01));

    await controller.setLoudnessEnabled(true);
    await controller.setLoudnessGain(3);
    expect(effects.loudnessEnabled, isTrue);
    expect(effects.loudnessGain, 3);

    await controller.reset();
    expect(effects.loudnessGain, 0);
    expect(effects.bandGains.values, everyElement(0));
    expect(
      SettingsRepository(prefs).loadAudioEffects().headroomEnabled,
      isTrue,
    );

    // A fresh container restores the stored profile.
    final reopened = _container(prefs, effects);
    await pumpEventQueue();
    expect(reopened.read(effectsControllerProvider).settings.presetId, 'flat');
  });

  test('auto headroom keeps boosted curves out of clipping', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects();
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    await controller.setEqualizerEnabled(true);
    await controller.selectPreset('bass');

    expect(container.read(effectsControllerProvider).preampDecibels, -7);
    expect(effects.preampDecibels, -7);
    // Every band lands at or below 0 dB, so the boost cannot clip.
    expect(effects.bandGains.values, everyElement(lessThanOrEqualTo(0.001)));
    expect(effects.bandGains[0], closeTo(-0.95, 0.05));

    await controller.setHeadroomEnabled(false);
    expect(container.read(effectsControllerProvider).preampDecibels, 0);
    expect(effects.preampDecibels, 0);
    expect(effects.bandGains[0], closeTo(6.05, 0.05));
  });

  test('editing a band of a one-point curve pins the other bands', () async {
    final prefs = await _freshPrefs();
    await SettingsRepository(prefs).setAudioEffects(
      const AudioEffectSettings(
        presetId: EqualizerPreset.customId,
        curve: EqualizerCurve([EqualizerPoint(1000, 3)]),
      ),
    );
    final effects = _FakeEffects();
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    await controller.setBandGain(0, -3);

    final curve = SettingsRepository(prefs).loadAudioEffects().curve;
    expect(curve.gainAt(60), -3);
    expect(curve.gainAt(230), 3);
    expect(curve.gainAt(14000), 3);
  });

  test('stored gains follow the band count the engine reports', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 7);
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    expect(container.read(effectsControllerProvider).engineReady, isTrue);
    await controller.setHeadroomEnabled(false);
    await controller.selectPreset('rock');

    final gains = container.read(effectsControllerProvider).bandGains;
    expect(gains, hasLength(7));
    expect(effects.bandGains, hasLength(7));
    // Seven log-spaced bands start at 31 Hz and end at 16 kHz, where the rock
    // table reads +4 dB and +2 dB.
    expect(effects.bandGains[0], closeTo(4, 0.01));
    expect(effects.bandGains[6], closeTo(2, 0.01));
  });

  test('curves queue up until the engine reports its layout', () async {
    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 3, ready: false);
    final container = _container(prefs, effects);
    final controller = container.read(effectsControllerProvider.notifier);
    await pumpEventQueue();

    // The reference bands are editable before anything has played.
    expect(container.read(effectsControllerProvider).engineReady, isFalse);
    expect(container.read(effectsControllerProvider).bandGains, hasLength(5));

    await controller.setHeadroomEnabled(false);
    await controller.setEqualizerEnabled(true);
    await controller.selectPreset('bass');
    expect(effects.equalizerEnabled, isTrue);
    expect(effects.curve, EqualizerPreset.bassBoost.curve);
    expect(effects.bandGains, isEmpty);

    // Playback starts: the engine reports three bands and samples the curve.
    effects.start();
    await pumpEventQueue();

    expect(container.read(effectsControllerProvider).engineReady, isTrue);
    expect(effects.bandGains, hasLength(3));
    expect(effects.bandGains[0], closeTo(7, 0.01));
    expect(effects.bandGains[2], closeTo(0, 0.01));
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
    expect(find.text('自动预增益'), findsOneWidget);
    expect(find.text('3.6kHz'), findsOneWidget);
    expect(find.text('230Hz'), findsOneWidget);

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    expect(effects.equalizerEnabled, isTrue);

    await tester.tap(find.text('低音增强'));
    await tester.pumpAndSettle();
    expect(effects.curve, EqualizerPreset.bassBoost.curve);
    expect(SettingsRepository(prefs).loadAudioEffects().presetId, 'bass');
    // Headroom keeps the strongest band at or below full scale.
    expect(effects.bandGains.values, everyElement(lessThanOrEqualTo(0.001)));

    await tester.tap(find.text('自动预增益'));
    await tester.pumpAndSettle();
    expect(effects.preampDecibels, 0);
    expect(effects.bandGains[0], closeTo(6.05, 0.05));

    await tester.tap(find.text('响度增强'));
    await tester.pumpAndSettle();
    expect(effects.loudnessEnabled, isTrue);

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(SettingsRepository(prefs).loadAudioEffects().presetId, 'flat');
    expect(
      SettingsRepository(prefs).loadAudioEffects().headroomEnabled,
      isTrue,
    );
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

    final stored = SettingsRepository(prefs).loadAudioEffects();
    expect(stored.presetId, EqualizerPreset.customId);
    expect(stored.curve.gainAt(60), greaterThan(0));
    // Editing one band leaves the other bands flat.
    expect(stored.curve.gainAt(230), 0);
    expect(stored.curve.gainAt(14000), 0);
  });

  testWidgets('a ten-band engine renders ten band sliders', (tester) async {
    tester.view.physicalSize = const Size(2400, 4200);
    addTearDown(tester.view.reset);

    final prefs = await _freshPrefs();
    final effects = _FakeEffects(bandCount: 10);
    await tester.pumpWidget(_wrap(prefs, effects, const EffectsPage()));
    await tester.pumpAndSettle();

    expect(find.text('频段（10 段）'), findsOneWidget);
    expect(find.text('16kHz'), findsOneWidget);
    // Ten band sliders plus the loudness slider.
    expect(find.byType(Slider), findsNWidgets(11));

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('低音增强'));
    await tester.pumpAndSettle();

    expect(effects.curve, EqualizerPreset.bassBoost.curve);
    expect(effects.bandGains, hasLength(10));
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
    // engine to report its layout: the reference bands are shown right away.
    expect(find.text('3.6kHz'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(6));

    await tester.tap(find.text('启用均衡器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动预增益'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(effects.bandGains, isEmpty);
    expect(
      SettingsRepository(prefs).loadAudioEffects().presetId,
      EqualizerPreset.customId,
    );

    // Playback starts: the engine swaps in its three bands and the queued
    // curve reaches it.
    effects.start();
    await tester.pumpAndSettle();

    expect(find.text('3.6kHz'), findsNothing);
    expect(find.byType(Slider), findsNWidgets(4));
    expect(effects.bandGains[0], greaterThan(0));
  });
}
