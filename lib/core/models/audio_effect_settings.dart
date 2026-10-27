import 'package:flowingpod/core/models/equalizer_preset.dart';
import 'package:flowingpod/core/models/json_utils.dart';

/// Persisted sound-effect preferences (equalizer + loudness enhancer).
class AudioEffectSettings {
  const AudioEffectSettings({
    this.equalizerEnabled = false,
    this.presetId = EqualizerPreset.flatId,
    this.bandGains = const <double>[],
    this.loudnessEnabled = false,
    this.loudnessGain = 0.0,
  });

  factory AudioEffectSettings.fromJson(Map<String, dynamic> json) =>
      AudioEffectSettings(
        equalizerEnabled: JsonUtils.boolean(json['equalizerEnabled']),
        presetId: JsonUtils.string(
          json['presetId'],
          fallback: EqualizerPreset.flatId,
        ),
        bandGains: JsonUtils.doubles(json['bandGains']),
        loudnessEnabled: JsonUtils.boolean(json['loudnessEnabled']),
        loudnessGain: JsonUtils.decimal(json['loudnessGain']),
      );

  /// Whether the platform equalizer modifies the output at all.
  final bool equalizerEnabled;

  /// Id of the selected [EqualizerPreset], `custom` once a slider is edited.
  final String presetId;

  /// Band gains in decibels matching the last known engine band count.
  final List<double> bandGains;

  /// Whether the loudness enhancer modifies the output.
  final bool loudnessEnabled;

  /// Loudness enhancer target gain in decibels.
  final double loudnessGain;

  Map<String, dynamic> toJson() => {
    'equalizerEnabled': equalizerEnabled,
    'presetId': presetId,
    'bandGains': bandGains,
    'loudnessEnabled': loudnessEnabled,
    'loudnessGain': loudnessGain,
  };

  AudioEffectSettings copyWith({
    bool? equalizerEnabled,
    String? presetId,
    List<double>? bandGains,
    bool? loudnessEnabled,
    double? loudnessGain,
  }) => AudioEffectSettings(
    equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
    presetId: presetId ?? this.presetId,
    bandGains: bandGains ?? this.bandGains,
    loudnessEnabled: loudnessEnabled ?? this.loudnessEnabled,
    loudnessGain: loudnessGain ?? this.loudnessGain,
  );
}
