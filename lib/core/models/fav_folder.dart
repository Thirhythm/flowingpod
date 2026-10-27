import 'json_utils.dart';

/// A favourite folder (收藏夹) belonging to the signed-in user.
class FavFolder {
  const FavFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
    this.attr = 0,
    this.isDefault = false,
  });

  final int id;
  final String title;
  final int mediaCount;

  /// Bit 1 of `attr` is set on user created folders; it is clear on the
  /// undeletable default 默认收藏夹.
  final int attr;

  final bool isDefault;

  factory FavFolder.fromJson(Map<String, dynamic> json) {
    final attr = JsonUtils.integer(json['attr']);
    return FavFolder(
      id: JsonUtils.integer(json['id']),
      title: JsonUtils.string(json['title'], fallback: '未命名收藏夹'),
      mediaCount: JsonUtils.integer(json['media_count']),
      attr: attr,
      isDefault: (attr & 2) == 0,
    );
  }
}
