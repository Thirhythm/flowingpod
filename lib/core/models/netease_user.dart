import 'json_utils.dart';

/// A signed-in NetEase Cloud Music account.
class NeteaseUser {
  const NeteaseUser({
    required this.userId,
    required this.nickname,
    this.avatarUrl = '',
    this.signature = '',
    this.vipType = 0,
  });

  final int userId;
  final String nickname;
  final String avatarUrl;
  final String signature;
  final int vipType;

  bool get isVip => vipType > 0;

  /// Parses the `profile` object of `/user/account`.
  factory NeteaseUser.fromProfile(Map<String, dynamic> json) => NeteaseUser(
    userId: JsonUtils.integer(json['userId']),
    nickname: JsonUtils.string(json['nickname'], fallback: '网易云用户'),
    avatarUrl: JsonUtils.string(json['avatarUrl']),
    signature: JsonUtils.string(json['signature']),
    vipType: JsonUtils.integer(json['vipType']),
  );
}
