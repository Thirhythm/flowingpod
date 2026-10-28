/// Sound quality levels accepted by the NetEase song URL API
/// (`/song/enhance/player/url/v1`'s `level` parameter).
///
/// The values are declared from lowest to highest quality, so [index] doubles
/// as the ranking used to decide which levels a song supports.
enum NeteaseQuality {
  standard('standard', '标准'),
  exhigh('exhigh', '极高'),
  lossless('lossless', '无损'),
  hires('hires', 'Hi-Res'),
  jyeffect('jyeffect', '高清臻音'),
  jymaster('jymaster', '超清母带'),
  sky('sky', '沉浸环绕声'),
  vivid('vivid', '臻音全景声');

  const NeteaseQuality(this.apiValue, this.label);

  /// Value the API expects in the `level` field.
  final String apiValue;

  /// Chinese label shown in the player UI.
  final String label;

  /// Quality used when the preferred one is not available for a song.
  static const NeteaseQuality fallback = NeteaseQuality.exhigh;

  /// Preference key inside [SharedPreferences].
  static const String storageKey = 'settings_netease_quality_v1';

  /// Reads a stored preference, falling back to [fallback] for unknown values.
  static NeteaseQuality fromStorage(Object? value) {
    final text = value?.toString();
    return values.firstWhere(
      (quality) => quality.name == text || quality.apiValue == text,
      orElse: () => fallback,
    );
  }

  /// Maps a `level` string returned by the API, or `null` when unknown.
  static NeteaseQuality? fromApiValue(String value) {
    for (final quality in values) {
      if (quality.apiValue == value) return quality;
    }
    return null;
  }
}
