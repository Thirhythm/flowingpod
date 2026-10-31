import 'dart:math' as math;

import 'package:flowingpod/core/models/equalizer_capabilities.dart';
import 'package:flowingpod/core/models/equalizer_curve.dart';
import 'package:flowingpod/core/models/equalizer_preset.dart';
import 'package:flowingpod/core/models/json_utils.dart';

/// Persisted sound-effect preferences (equalizer + loudness enhancer).
class AudioEffectSettings {
  const AudioEffectSettings({
    this.equalizerEnabled = false,
    this.presetId = EqualizerPreset.flatId,
    this.curve = EqualizerCurve.flat,
    this.headroomEnabled = true,
    this.loudnessEnabled = false,
    this.loudnessGain = 0.0,
  });

  factory AudioEffectSettings.fromJson(Map<String, dynamic> json) {
    final legacyGains = JsonUtils.doubles(json['bandGains']);
    return AudioEffectSettings(
      equalizerEnabled: JsonUtils.boolean(json['equalizerEnabled']),
      presetId: JsonUtils.string(
        json['presetId'],
        fallback: EqualizerPreset.flatId,
      ),
      // Entries written before curves existed stored one gain per band and no
      // frequencies; they are placed on the reference layout.
      curve:
          EqualizerCurve.fromJson(json['bandCurve']) ??
          _curveFromLegacyGains(legacyGains),
      headroomEnabled: JsonUtils.boolean(
        json['headroomEnabled'],
        fallback: true,
      ),
      loudnessEnabled: JsonUtils.boolean(json['loudnessEnabled']),
      loudnessGain: JsonUtils.decimal(json['loudnessGain']),
    );
  }

  /// Whether the platform equalizer modifies the output at all.
  final bool equalizerEnabled;

  /// Id of the selected [EqualizerPreset], `custom` once a band is edited.
  final String presetId;

  /// Frequency response applied to the equalizer.
  final EqualizerCurve curve;

  /// Whether boosts are offset by a matching attenuation, so a strong curve
  /// cannot push the output past full scale.
  final bool headroomEnabled;

  /// Whether the loudness enhancer modifies the output.
  final bool loudnessEnabled;

  /// Loudness enhancer target gain in decibels.
  final double loudnessGain;

  /// Attenuation applied on top of [curve] to leave headroom for its boosts;
  /// zero while [headroomEnabled] is off or nothing is boosted.
  double get preampDecibels {
    if (!headroomEnabled) return 0;
    final peak = curve.peakGain;
    return peak > 0 ? -peak : 0;
  }

  Map<String, dynamic> toJson() => {
    'equalizerEnabled': equalizerEnabled,
    'presetId': presetId,
    'bandCurve': curve.toJson(),
    'headroomEnabled': headroomEnabled,
    'loudnessEnabled': loudnessEnabled,
    'loudnessGain': loudnessGain,
  };

  AudioEffectSettings copyWith({
    bool? equalizerEnabled,
    String? presetId,
    EqualizerCurve? curve,
    bool? headroomEnabled,
    bool? loudnessEnabled,
    double? loudnessGain,
  }) => AudioEffectSettings(
    equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
    presetId: presetId ?? this.presetId,
    curve: curve ?? this.curve,
    headroomEnabled: headroomEnabled ?? this.headroomEnabled,
    loudnessEnabled: loudnessEnabled ?? this.loudnessEnabled,
    loudnessGain: loudnessGain ?? this.loudnessGain,
  );

  /// Places gains stored before curves existed on frequencies: the reference
  /// layout for five gains, a logarithmic spread from 31 Hz to 16 kHz
  /// otherwise.
  static EqualizerCurve _curveFromLegacyGains(List<double> gains) {
    if (gains.isEmpty) return EqualizerCurve.flat;
    final reference = EqualizerCapabilities.reference;
    final frequencies = gains.length == reference.bands.length
        ? reference.centerFrequencies
        : [
            for (var i = 0; i < gains.length; i++)
              _legacyFrequency(i, gains.length),
          ];
    return EqualizerCurve([
      for (var i = 0; i < gains.length; i++)
        EqualizerPoint(frequencies[i], gains[i]),
    ]);
  }

  static double _legacyFrequency(int index, int count) {
    if (count == 1) return 1000;
    const low = 31.0;
    const high = 16000.0;
    return low * math.pow(high / low, index / (count - 1)).toDouble();
  }
}
