/// Upstream service a playable track comes from.
enum TrackSource {
  bilibili,
  netease;

  static TrackSource fromStorage(Object? value) => switch (value) {
    'netease' => TrackSource.netease,
    _ => TrackSource.bilibili,
  };
}
