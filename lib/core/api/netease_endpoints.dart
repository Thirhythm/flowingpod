/// Paths of the NetEase web API used through `NeteaseClient`'s `weapi`
/// encryption.
abstract final class NeteaseEndpoints {
  /// Host serving the `weapi` routes.
  static const String host = 'https://music.163.com';

  // --- Account / authentication -------------------------------------------
  static const String account = '/nuser/account/get';
  static const String logout = '/logout';

  /// QR login: request a key, render the URL, then poll the check endpoint.
  static const String qrKey = '/login/qrcode/unikey';
  static const String qrCheck = '/login/qrcode/client/login';

  // --- Phone (SMS) login --------------------------------------------------
  static const String smsSend = '/sms/captcha/sent';
  static const String smsLogin = '/w/login/cellphone';

  // --- Search -------------------------------------------------------------
  static const String search = '/cloudsearch/pc';
  static const String searchSuggest = '/search/suggest/web';

  // --- Songs --------------------------------------------------------------
  static const String songUrl = '/song/enhance/player/url';
  static const String songDetail = '/v3/song/detail';
  static const String like = '/radio/like';

  // --- Playlists ----------------------------------------------------------
  static const String userPlaylist = '/user/playlist';
  static const String playlistCreate = '/playlist/create';
  static const String playlistNameUpdate = '/playlist/name/update';
  static const String playlistDelete = '/playlist/remove';
  static const String playlistTracks = '/playlist/manipulate/tracks';
  static const String playlistDetail = '/v6/playlist/detail';
}
