import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/bili_endpoints.dart';
import 'package:flowingpod/core/models/bili_user.dart';
import 'package:flowingpod/core/models/json_utils.dart';

/// A generated login QR code.
class QrSession {
  const QrSession({required this.url, required this.key});

  /// Content that must be rendered as a QR code.
  final String url;

  /// Opaque key used to poll the login state.
  final String key;
}

enum QrLoginStatus { waiting, scanned, expired, success, failed }

class QrPollResult {
  const QrPollResult(this.status, {this.message});

  final QrLoginStatus status;
  final String? message;
}

/// A geetest challenge that must be solved before an SMS code can be sent.
class CaptchaChallenge {
  const CaptchaChallenge({
    required this.token,
    required this.gt,
    required this.challenge,
  });

  /// Login API token that has to be echoed back on `sms/send`.
  final String token;

  /// Geetest id used to initialise the widget.
  final String gt;

  /// Geetest challenge; the widget returns an updated one once solved.
  final String challenge;
}

/// Handles QR-code and phone (SMS) login, session inspection and logout.
class AuthRepository {
  AuthRepository(this._client);

  /// `source` parameter the web login page sends upstream.
  static const String loginSource = 'main_web';

  /// Page the login API redirects to once the session is established.
  static const String _loginGoUrl = 'https://www.bilibili.com';

  final BiliClient _client;

  bool get isLoggedIn => _client.isLoggedIn;

  /// Requests a fresh login QR code.
  Future<QrSession> createQrSession() async {
    final response = await _client.getJson(
      BiliEndpoints.qrGenerate,
      baseUrl: BiliEndpoints.passportBase,
    );
    final data = JsonUtils.map(response['data']);
    final url = JsonUtils.string(data['url']);
    final key = JsonUtils.string(data['qrcode_key']);
    if (url.isEmpty || key.isEmpty) {
      throw const BiliApiException(
        code: -1,
        message: '无法获取登录二维码，请稍后重试',
        path: BiliEndpoints.qrGenerate,
      );
    }
    return QrSession(url: url, key: key);
  }

  /// Polls the state of a previously created QR session.
  Future<QrPollResult> pollQrSession(String key) async {
    final response = await _client.getJson(
      BiliEndpoints.qrPoll,
      baseUrl: BiliEndpoints.passportBase,
      query: {'qrcode_key': key},
    );
    final data = JsonUtils.map(response['data']);
    final code = JsonUtils.integer(data['code']);

    switch (code) {
      case 0:
        await _persistLoginCookies(data);
        return const QrPollResult(QrLoginStatus.success);
      case 86090:
        return const QrPollResult(QrLoginStatus.scanned);
      case 86038:
        return const QrPollResult(QrLoginStatus.expired);
      case 86101:
        return const QrPollResult(QrLoginStatus.waiting);
      default:
        return QrPollResult(
          QrLoginStatus.failed,
          message: JsonUtils.string(data['message'], fallback: '登录失败'),
        );
    }
  }

  /// Requests a fresh geetest challenge for phone login.
  Future<CaptchaChallenge> createCaptcha() async {
    final response = await _client.getJson(
      BiliEndpoints.captcha,
      baseUrl: BiliEndpoints.passportBase,
      query: {'source': loginSource},
    );
    final data = JsonUtils.map(response['data']);
    final geetest = JsonUtils.map(data['geetest']);
    final token = JsonUtils.string(data['token']);
    final gt = JsonUtils.string(geetest['gt']);
    final challenge = JsonUtils.string(geetest['challenge']);
    if (token.isEmpty || gt.isEmpty || challenge.isEmpty) {
      throw const BiliApiException(
        code: -1,
        message: '无法获取人机验证参数，请稍后重试',
        path: BiliEndpoints.captcha,
      );
    }
    return CaptchaChallenge(token: token, gt: gt, challenge: challenge);
  }

  /// Sends an SMS code to [tel] and returns the `captcha_key` used to log in.
  ///
  /// [challenge], [validate] and [seccode] come from the solved geetest widget;
  /// [cid] is the international dialling code of [tel].
  Future<String> sendSmsCode({
    required String cid,
    required String tel,
    required CaptchaChallenge captcha,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    try {
      final response = await _client.postForm(
        BiliEndpoints.smsSend,
        {
          'cid': cid,
          'tel': tel,
          'source': loginSource,
          'token': captcha.token,
          'challenge': challenge,
          'validate': validate,
          'seccode': seccode,
        },
        baseUrl: BiliEndpoints.passportBase,
        requireLogin: false,
      );
      final key = JsonUtils.string(
        JsonUtils.map(response['data'])['captcha_key'],
      );
      if (key.isEmpty) {
        throw const BiliApiException(
          code: -1,
          message: '短信验证码发送失败，请稍后重试',
          path: BiliEndpoints.smsSend,
        );
      }
      return key;
    } on BiliApiException catch (error) {
      throw _smsError(error, BiliEndpoints.smsSend);
    }
  }

  /// Completes phone login with the received [code] and stores the cookies.
  ///
  /// [captchaKey] is the value returned by [sendSmsCode].
  Future<void> loginWithSmsCode({
    required String cid,
    required String tel,
    required String code,
    required String captchaKey,
  }) async {
    Map<String, dynamic> data;
    try {
      final response = await _client.postForm(
        BiliEndpoints.smsLogin,
        {
          'cid': cid,
          'tel': tel,
          'code': code,
          'source': loginSource,
          'captcha_key': captchaKey,
          'go_url': _loginGoUrl,
          'keep': true,
        },
        baseUrl: BiliEndpoints.passportBase,
        requireLogin: false,
      );
      data = JsonUtils.map(response['data']);
    } on BiliApiException catch (error) {
      throw _smsError(error, BiliEndpoints.smsLogin);
    }
    await _persistLoginCookies(data);
    if (!_client.isLoggedIn) {
      // A non-zero `status` means the account still needs a security check.
      final status = JsonUtils.integer(data['status']);
      throw BiliApiException(
        code: status,
        message: status == 0 ? '登录失败，请重试' : '账号需要额外安全验证，请稍后重试',
        path: BiliEndpoints.smsLogin,
      );
    }
  }

  /// Returns the signed-in account, or `null` when no session is active.
  Future<BiliUser?> fetchCurrentUser() async {
    final data = await _client.fetchNav();
    if (!JsonUtils.boolean(data['isLogin'])) return null;
    final user = BiliUser.fromNav(data);
    try {
      final stat = await _client.getJson(BiliEndpoints.navStat);
      final statData = JsonUtils.map(stat['data']);
      return user.copyWith(
        following: JsonUtils.integer(statData['following']),
        follower: JsonUtils.integer(statData['follower']),
      );
    } on BiliApiException {
      return user;
    }
  }

  /// Clears the session locally and invalidates it on the server.
  Future<void> logout() async {
    final csrf = _client.cookies.csrfToken;
    try {
      if (_client.isLoggedIn && csrf != null && csrf.isNotEmpty) {
        await _client.postForm(
          BiliEndpoints.exitLogin,
          {'biliCSRF': csrf},
          baseUrl: BiliEndpoints.passportBase,
        );
      }
    } on BiliApiException {
      // The remote session is best-effort; the local cookies are cleared below.
    } finally {
      await _client.cookies.clear();
    }
  }

  /// Upstream `message` values for the documented SMS codes are unreliable
  /// (they are often `"0"`), so the common ones are translated locally.
  static const Map<int, String> _smsErrors = {
    1002: '手机号格式错误',
    1003: '验证码已发送，请稍后重试',
    1006: '短信验证码错误，请重新输入',
    1007: '短信验证码已过期，请重新获取',
    1025: '该手机号已被封禁，无法登录',
    2400: '人机验证已过期，请重新验证',
    2406: '人机验证失败，请重新验证',
    86203: '短信发送次数已达上限，请稍后重试',
  };

  static BiliApiException _smsError(BiliApiException error, String path) {
    final mapped = _smsErrors[error.code];
    if (mapped != null) {
      return BiliApiException(code: error.code, message: mapped, path: path);
    }
    if (error.message.isEmpty || error.message == '0') {
      return BiliApiException(
        code: error.code,
        message: '操作失败，请稍后重试',
        path: path,
      );
    }
    return error;
  }

  /// The web login flow returns the session cookies via `Set-Cookie`
  /// (already captured by the client) and again inside `data.url`. The latter
  /// is only used for cookies the response headers did not provide.
  ///
  /// Values are parsed from the raw query string without percent-decoding,
  /// because `SESSDATA` itself contains escaped characters.
  Future<void> _persistLoginCookies(Map<String, dynamic> data) async {
    final url = JsonUtils.string(data['url']);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final rawQuery = uri.query;

    final missing = <String, String>{};
    for (final name in const [
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
    ]) {
      final existing = _client.cookies[name];
      if (existing != null && existing.isNotEmpty) continue;
      final value = _rawQueryValue(rawQuery, name);
      if (value != null && value.isNotEmpty) missing[name] = value;
    }
    if (missing.isNotEmpty) {
      await _client.cookies.setAll(missing);
    }
  }

  static String? _rawQueryValue(String rawQuery, String name) {
    for (final pair in rawQuery.split('&')) {
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      if (pair.substring(0, separator) == name) {
        return pair.substring(separator + 1);
      }
    }
    return null;
  }
}
