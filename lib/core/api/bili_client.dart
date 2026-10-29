import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'bili_endpoints.dart';
import 'cookie_store.dart';
import 'wbi_signer.dart';

/// Low level HTTP client for the public Bilibili web API.
///
/// Responsibilities:
/// * attach the browser-like headers the API expects,
/// * inject and persist session cookies,
/// * transparently sign requests that require a WBI signature.
class BiliClient {
  BiliClient._(this._dio, this.cookies);

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  static const String _referer = 'https://www.bilibili.com/';

  static const Duration _wbiKeyTtl = Duration(hours: 6);

  final Dio _dio;
  final CookieStore cookies;

  WbiSigner? _wbiSigner;
  DateTime? _wbiSignerFetchedAt;

  /// Pending anonymous identity bootstrap. Requests await it so the very first
  /// call still carries `buvid3`, without delaying the first frame.
  Future<void> _bootstrap = Future<void>.value();

  static const Duration _bootstrapTimeout = Duration(seconds: 8);

  /// Builds a client and starts the anonymous device identity in the
  /// background; app startup never blocks on the network.
  static Future<BiliClient> create() async {
    final store = await CookieStore.create();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        responseType: ResponseType.json,
        // Bilibili signals business errors in the body, not via HTTP status.
        validateStatus: (_) => true,
      ),
    );

    final client = BiliClient._(dio, store);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll(client._requestHeaders());
          final cookie = client.cookies.headerFor(options.uri);
          if (cookie.isNotEmpty) options.headers['Cookie'] = cookie;
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final setCookie = response.headers['set-cookie'];
          if (setCookie != null && setCookie.isNotEmpty) {
            await store.applySetCookie(setCookie);
          }
          handler.next(response);
        },
      ),
    );

    client._bootstrap = client.ensureDeviceIdentity();
    return client;
  }

  /// Whether a logged-in session is available.
  bool get isLoggedIn => cookies.hasSession;

  Map<String, String> _requestHeaders() => {
    'User-Agent': userAgent,
    'Referer': _referer,
    'Origin': 'https://www.bilibili.com',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// Requests an anonymous `buvid3`/`buvid4` pair if none is stored yet.
  ///
  /// Uses a raw request so it can run before [getJson] awaits [_bootstrap].
  Future<void> ensureDeviceIdentity() async {
    if ((cookies['buvid3'] ?? '').isNotEmpty) return;
    try {
      final response = await _sendRaw(
        BiliEndpoints.apiBase,
        BiliEndpoints.fingerSpi,
        const {},
      ).timeout(_bootstrapTimeout);
      final payload = response['data'];
      if (payload is Map) {
        final values = <String, String>{};
        final buvid3 = payload['b_3'];
        final buvid4 = payload['b_4'];
        if (buvid3 is String && buvid3.isNotEmpty) values['buvid3'] = buvid3;
        if (buvid4 is String && buvid4.isNotEmpty) values['buvid4'] = buvid4;
        values['b_nut'] = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
        await cookies.setAll(values);
      }
    } catch (_) {
      // Device identity is best-effort; the API also accepts requests without it.
    }
  }

  /// Performs a `GET` request and returns the parsed JSON body.
  ///
  /// When [signed] is `true` the parameters are WBI signed; if the API reports
  /// an invalid signature the keys are refreshed and the request retried once.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, Object?>? query,
    bool signed = false,
    String baseUrl = BiliEndpoints.apiBase,
    bool requireLogin = false,
  }) async {
    _assertLogin(requireLogin, path);
    await _bootstrap;
    final params = _stringify(query);

    if (!signed) {
      return _send(baseUrl, path, params);
    }

    var signer = await _ensureWbiSigner();
    var result = await _send(baseUrl, path, signer.sign(params));
    if (_isVoucher(result)) {
      signer = await _refreshWbiSigner();
      result = await _send(baseUrl, path, signer.sign(params));
    }
    return result;
  }

  /// Performs a form encoded `POST` request and returns the parsed JSON body.
  Future<Map<String, dynamic>> postForm(
    String path,
    Map<String, Object?> body, {
    String baseUrl = BiliEndpoints.apiBase,
    bool requireLogin = true,
  }) async {
    _assertLogin(requireLogin, path);
    await _bootstrap;
    final uri = _buildUri(baseUrl, path, const {});
    try {
      final response = await _dio.postUri<dynamic>(
        uri,
        data: _stringify(body),
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: _requestHeaders(),
        ),
      );
      final decoded = _decodeBody(response, path);
      _assertOk(decoded, path);
      return decoded;
    } on DioException catch (error) {
      throw _transportError(error, path);
    }
  }

  Future<Map<String, dynamic>> _send(
    String baseUrl,
    String path,
    Map<String, String> params,
  ) async {
    final response = await _sendRaw(baseUrl, path, params);
    _assertOk(response, path);
    return response;
  }

  /// Performs the request and validates the transport layer only, leaving the
  /// business `code` to the caller.
  Future<Map<String, dynamic>> _sendRaw(
    String baseUrl,
    String path,
    Map<String, String> params,
  ) async {
    final uri = _buildUri(baseUrl, path, params);
    try {
      final response = await _dio.getUri<dynamic>(uri);
      return _decodeBody(response, path);
    } on DioException catch (error) {
      throw _transportError(error, path);
    }
  }

  /// Decodes a response body into a JSON object.
  ///
  /// Some endpoints answer without a `Content-Type`, in which case Dio hands
  /// back the raw body instead of decoded JSON, so a string body is decoded
  /// here as a fallback.
  Map<String, dynamic> _decodeBody(Response<dynamic> response, String path) {
    Object? body = response.data;
    if (body is String) {
      try {
        body = body.isEmpty ? null : jsonDecode(body);
      } on FormatException {
        body = null;
      }
    }
    if (body is! Map) {
      throw BiliApiException(
        code: response.statusCode ?? -1,
        message: '响应数据格式异常',
        path: path,
      );
    }
    return body.map((key, value) => MapEntry('$key', value));
  }

  /// Throws unless the response carries a successful business code.
  void _assertOk(Map<String, dynamic> response, String path) {
    final code = (response['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final message = response['message'] ?? response['msg'] ?? '请求失败';
      throw BiliApiException(code: code, message: '$message', path: path);
    }
  }

  void _assertLogin(bool requireLogin, String path) {
    if (requireLogin && !cookies.hasSession) {
      throw BiliApiException(code: -101, message: '账号未登录', path: path);
    }
  }

  Map<String, String> _stringify(Map<String, Object?>? source) {
    if (source == null) return const {};
    final result = <String, String>{};
    source.forEach((key, value) {
      if (value != null) result[key] = value.toString();
    });
    return result;
  }

  Uri _buildUri(String baseUrl, String path, Map<String, String> params) {
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return Uri.parse(query.isEmpty ? '$baseUrl$path' : '$baseUrl$path?$query');
  }

  bool _isVoucher(Map<String, dynamic> response) {
    final data = response['data'];
    return data is Map && data.containsKey('v_voucher');
  }

  BiliApiException _transportError(DioException error, String path) {
    final message = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '网络连接超时，请稍后重试',
      DioExceptionType.connectionError => '网络连接失败，请检查网络设置',
      DioExceptionType.badCertificate => '证书校验失败',
      DioExceptionType.cancel => '请求已取消',
      _ => '网络请求失败：${error.message ?? error.type.name}',
    };
    return BiliApiException(code: -1, message: message, path: path);
  }

  Future<WbiSigner> _ensureWbiSigner() async {
    final cached = _wbiSigner;
    final fetchedAt = _wbiSignerFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _wbiKeyTtl) {
      return cached;
    }
    return _refreshWbiSigner();
  }

  Future<WbiSigner> _refreshWbiSigner() async {
    // `nav` answers with `code: -101` for anonymous visitors but still returns
    // the WBI keys in `data.wbi_img`, so the business code is ignored here.
    final response = await _sendRaw(
      BiliEndpoints.apiBase,
      BiliEndpoints.nav,
      const {},
    );
    final data = response['data'];
    if (data is Map) {
      final wbiImg = data['wbi_img'];
      if (wbiImg is Map) {
        final imgKey = _fileName(wbiImg['img_url']);
        final subKey = _fileName(wbiImg['sub_url']);
        if (imgKey != null && subKey != null) {
          final signer = WbiSigner(imgKey: imgKey, subKey: subKey);
          _wbiSigner = signer;
          _wbiSignerFetchedAt = DateTime.now();
          return signer;
        }
      }
    }
    throw const BiliApiException(
      code: -1,
      message: '无法获取 WBI 签名密钥',
      path: BiliEndpoints.nav,
    );
  }

  static String? _fileName(Object? url) {
    if (url is! String || url.isEmpty) return null;
    final lastSegment = url.split('/').last;
    final dot = lastSegment.indexOf('.');
    return dot <= 0 ? lastSegment : lastSegment.substring(0, dot);
  }

  /// Convenience helper returning the `nav` payload.
  Future<Map<String, dynamic>> fetchNav() async {
    final response = await getJson(BiliEndpoints.nav);
    final data = response['data'];
    return data is Map ? data.map((k, v) => MapEntry('$k', v)) : <String, dynamic>{};
  }
}
