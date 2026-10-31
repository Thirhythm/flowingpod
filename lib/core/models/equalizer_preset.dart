import 'package:flowingpod/core/models/equalizer_curve.dart';

/// A named frequency response applied to the equalizer in one tap.
///
/// Responses are written for the ten bands of a standard octave equalizer and
/// stored as a curve, so a device with any other band layout (five bands, or
/// fifteen) gets the same shape sampled at its own band frequencies instead of
/// a table stretched by band index.
class EqualizerPreset {
  const EqualizerPreset(this.id, this.label, this.curve);

  /// Frequencies the preset tables are anchored at, in hertz.
  static const List<double> anchorFrequencies = [
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];

  /// Id of the free-form profile edited through the band sliders.
  static const String customId = 'custom';

  /// Id of the neutral profile.
  static const String flatId = 'flat';

  /// Profiles offered in the picker, in display order.
  static final List<EqualizerPreset> values = [
    flat,
    pop,
    rock,
    electronic,
    hiphop,
    jazz,
    classical,
    bassBoost,
    vocal,
  ];

  static final EqualizerPreset flat = _preset(flatId, '标准', const [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);

  static final EqualizerPreset pop = _preset('pop', '流行', const [
    -1,
    0,
    1,
    2,
    2,
    1,
    0,
    -1,
    -1,
    -1,
  ]);

  static final EqualizerPreset rock = _preset('rock', '摇滚', const [
    4,
    3,
    1,
    -1,
    -1,
    0,
    1,
    2,
    3,
    2,
  ]);

  static final EqualizerPreset electronic = _preset('electronic', '电子', const [
    6,
    5,
    2,
    0,
    -2,
    -1,
    1,
    3,
    4,
    3,
  ]);

  static final EqualizerPreset hiphop = _preset('hiphop', '嘻哈', const [
    6,
    5,
    4,
    2,
    0,
    -1,
    0,
    1,
    2,
    2,
  ]);

  static final EqualizerPreset jazz = _preset('jazz', '爵士', const [
    3,
    2,
    1,
    2,
    -1,
    -1,
    0,
    1,
    2,
    2,
  ]);

  static final EqualizerPreset classical = _preset('classical', '古典', const [
    2,
    1,
    0,
    0,
    0,
    0,
    -1,
    -1,
    1,
    2,
  ]);

  static final EqualizerPreset bassBoost = _preset('bass', '低音增强', const [
    7,
    6,
    5,
    3,
    1,
    0,
    0,
    0,
    0,
    0,
  ]);

  static final EqualizerPreset vocal = _preset('vocal', '人声增强', const [
    -2,
    -2,
    -1,
    1,
    3,
    4,
    3,
    1,
    0,
    -1,
  ]);

  /// The profile shown while the band sliders are edited by hand. The applied
  /// response always comes from the stored settings, not this placeholder.
  static const EqualizerPreset custom = EqualizerPreset(
    customId,
    '自定义',
    EqualizerCurve.flat,
  );

  final String id;
  final String label;

  /// Frequency response of the profile.
  final EqualizerCurve curve;

  bool get isCustom => id == customId;

  /// Restores a persisted profile, falling back to [flat].
  static EqualizerPreset byId(String? id) {
    for (final preset in values) {
      if (preset.id == id) return preset;
    }
    return id == customId ? custom : flat;
  }

  /// The response sampled at [frequencies], e.g. the centre frequencies the
  /// platform equalizer reports.
  List<double> gainsFor(Iterable<double> frequencies) =>
      curve.sampleAt(frequencies);

  static EqualizerPreset _preset(String id, String label, List<double> gains) {
    assert(
      gains.length == anchorFrequencies.length,
      'a preset needs one gain per anchor frequency',
    );
    return EqualizerPreset(
      id,
      label,
      EqualizerCurve([
        for (var i = 0; i < anchorFrequencies.length; i++)
          EqualizerPoint(anchorFrequencies[i], gains[i]),
      ]),
    );
  }
}
