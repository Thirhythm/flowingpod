/// A frequency band of the platform equalizer, in hertz.
class EqualizerBand {
  const EqualizerBand({
    required this.lowerFrequency,
    required this.upperFrequency,
    required this.centerFrequency,
  });

  final double lowerFrequency;
  final double upperFrequency;
  final double centerFrequency;
}

/// Band layout and gain range reported by the playback engine.
class EqualizerCapabilities {
  const EqualizerCapabilities({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });

  /// The five bands of a typical Android equalizer, offered for editing while
  /// the engine still reports no layout of its own.
  static const EqualizerCapabilities reference = EqualizerCapabilities(
    minDecibels: -15,
    maxDecibels: 15,
    bands: [
      EqualizerBand(
        lowerFrequency: 30,
        upperFrequency: 120,
        centerFrequency: 60,
      ),
      EqualizerBand(
        lowerFrequency: 120,
        upperFrequency: 450,
        centerFrequency: 230,
      ),
      EqualizerBand(
        lowerFrequency: 450,
        upperFrequency: 1800,
        centerFrequency: 910,
      ),
      EqualizerBand(
        lowerFrequency: 1800,
        upperFrequency: 7000,
        centerFrequency: 3600,
      ),
      EqualizerBand(
        lowerFrequency: 7000,
        upperFrequency: 20000,
        centerFrequency: 14000,
      ),
    ],
  );

  /// The ten fixed bands of the native dynamics equalizer used on Android,
  /// where the platform effect allows a fixed layout instead of the device
  /// equalizer's own bands.
  static const EqualizerCapabilities nativeTenBand = EqualizerCapabilities(
    minDecibels: -12,
    maxDecibels: 12,
    bands: [
      EqualizerBand(
        lowerFrequency: 20,
        upperFrequency: 44,
        centerFrequency: 31,
      ),
      EqualizerBand(
        lowerFrequency: 44,
        upperFrequency: 88,
        centerFrequency: 62,
      ),
      EqualizerBand(
        lowerFrequency: 88,
        upperFrequency: 177,
        centerFrequency: 125,
      ),
      EqualizerBand(
        lowerFrequency: 177,
        upperFrequency: 354,
        centerFrequency: 250,
      ),
      EqualizerBand(
        lowerFrequency: 354,
        upperFrequency: 707,
        centerFrequency: 500,
      ),
      EqualizerBand(
        lowerFrequency: 707,
        upperFrequency: 1414,
        centerFrequency: 1000,
      ),
      EqualizerBand(
        lowerFrequency: 1414,
        upperFrequency: 2828,
        centerFrequency: 2000,
      ),
      EqualizerBand(
        lowerFrequency: 2828,
        upperFrequency: 5657,
        centerFrequency: 4000,
      ),
      EqualizerBand(
        lowerFrequency: 5657,
        upperFrequency: 11314,
        centerFrequency: 8000,
      ),
      EqualizerBand(
        lowerFrequency: 11314,
        upperFrequency: 20000,
        centerFrequency: 16000,
      ),
    ],
  );

  /// Smallest band gain the engine accepts.
  final double minDecibels;

  /// Largest band gain the engine accepts.
  final double maxDecibels;

  /// Bands ordered from low to high frequency.
  final List<EqualizerBand> bands;

  /// Centre frequencies of [bands], low to high.
  List<double> get centerFrequencies => [
    for (final band in bands) band.centerFrequency,
  ];
}
