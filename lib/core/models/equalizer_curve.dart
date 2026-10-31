import 'dart:math' as math;

/// One control point of an [EqualizerCurve]: a gain at a frequency.
class EqualizerPoint {
  const EqualizerPoint(this.frequency, this.gain);

  /// Center frequency in hertz; must be positive.
  final double frequency;

  /// Gain in decibels.
  final double gain;

  @override
  bool operator ==(Object other) =>
      other is EqualizerPoint &&
      other.frequency == frequency &&
      other.gain == gain;

  @override
  int get hashCode => Object.hash(frequency, gain);
}

/// A frequency response made of control points, ordered low to high.
///
/// Gains between points are interpolated on a logarithmic frequency axis,
/// which matches how pitch is perceived and lets a profile designed for one
/// band layout reproduce its shape on the bands of any device. Outside the
/// control points the gain of the nearest point is held.
class EqualizerCurve {
  /// [points] must already be sorted by ascending frequency.
  const EqualizerCurve(this.points);

  /// The neutral response: every frequency at 0 dB.
  static const EqualizerCurve flat = EqualizerCurve(<EqualizerPoint>[]);

  final List<EqualizerPoint> points;

  /// Whether no point shapes the response, i.e. it is flat.
  bool get isEmpty => points.isEmpty;

  /// Highest gain of any control point, never below zero.
  double get peakGain =>
      points.fold(0.0, (peak, point) => math.max(peak, point.gain));

  /// Gain in decibels at [frequency].
  double gainAt(double frequency) {
    if (points.isEmpty) return 0;
    if (frequency <= points.first.frequency) return points.first.gain;
    if (frequency >= points.last.frequency) return points.last.gain;
    for (var i = 1; i < points.length; i++) {
      final high = points[i];
      if (frequency <= high.frequency) {
        final low = points[i - 1];
        final position =
            (math.log(frequency) - math.log(low.frequency)) /
            (math.log(high.frequency) - math.log(low.frequency));
        return low.gain + (high.gain - low.gain) * position;
      }
    }
    return points.last.gain;
  }

  /// The response sampled at [frequencies], in the same order.
  List<double> sampleAt(Iterable<double> frequencies) => [
    for (final frequency in frequencies) gainAt(frequency),
  ];

  /// A copy carrying [gain] at [frequency]. A point within 1 % of the
  /// frequency is replaced so editing the same band never piles up points.
  EqualizerCurve withGainAt(double frequency, double gain) {
    if (frequency <= 0) return this;
    final points = <EqualizerPoint>[
      for (final point in this.points)
        if ((point.frequency - frequency).abs() / frequency >= 0.01) point,
      EqualizerPoint(frequency, gain),
    ]..sort((a, b) => a.frequency.compareTo(b.frequency));
    return EqualizerCurve(points);
  }

  List<List<double>> toJson() => [
    for (final point in points) [point.frequency, point.gain],
  ];

  /// Restores a persisted response; `null` when [raw] is not a list.
  static EqualizerCurve? fromJson(Object? raw) {
    if (raw is! List) return null;
    final points = <EqualizerPoint>[];
    for (final item in raw) {
      if (item is! List || item.length < 2) continue;
      final frequency = item[0];
      final gain = item[1];
      if (frequency is num && gain is num && frequency > 0) {
        points.add(EqualizerPoint(frequency.toDouble(), gain.toDouble()));
      }
    }
    points.sort((a, b) => a.frequency.compareTo(b.frequency));
    return EqualizerCurve(points);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EqualizerCurve || other.points.length != points.length) {
      return false;
    }
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(points);

  @override
  String toString() =>
      'EqualizerCurve(${points.map((p) => '${p.frequency}Hz:${p.gain}dB').join(', ')})';
}
