import 'dart:convert';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/api/bili_client.dart';
import 'package:flowingpod/core/api/netease_cookie_store.dart';
import 'package:flowingpod/core/api/netease_crypto.dart';
import 'package:flowingpod/core/api/netease_endpoints.dart';
import 'package:flowingpod/core/models/json_utils.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Low level HTTP client for the NetEase web API.
///
/// Requests are encrypted locally with the same `weapi` scheme the web player
/// uses, so no proxy or self-hosted API service is required.
class NeteaseClient {
  NeteaseClient(this.cookies)
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );

  /// Loads the encrypted cookie jar before the client is constructed.
  static Future<NeteaseClient> create(SharedPreferences prefs) async =>
      NeteaseClient(await NeteaseCookieStore.load(prefs));

  final Dio _dio;
  final NeteaseCookieStore cookies;

  bool get isLoggedIn => cookies.hasSession;

  /// Sends an encrypted request and returns the decoded JSON body.
  ///
  /// The business `code` is not validated here, because login polling routes
  /// use it as a status value. Call [expectOk] for ordinary operations.
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, Object?> data = const {},
    bool requireLogin = false,
  }) async {
    if (requireLogin && !isLoggedIn) {
      throw BiliApiException(code: -101, message: '网易云账号未登录', path: path);
    }

    final encrypted = NeteaseCrypto.weapi({
      ...data,
      // The web player always sends the CSRF token (empty before login) and
      // opts out of encrypted responses.
      'csrf_token': cookies['__csrf'] ?? '',
      'e_r': false,
    });
    final uri = Uri.parse('${NeteaseEndpoints.host}/weapi$path');
    final cookie = cookies.headerFor(uri);
    try {
      final response = await _dio.postUri<dynamic>(
        uri,
        data: encrypted,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'User-Agent': BiliClient.userAgent,
            'Referer': 'https://music.163.com',
            'Origin': 'https://music.163.com',
            'Accept': 'application/json, text/plain, */*',
            if (cookie.isNotEmpty) 'Cookie': cookie,
          },
        ),
      );
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        await cookies.applySetCookie(setCookie);
      }
      return _decodeBody(response, path);
    } on DioException catch (error) {
      throw _transportError(error, path);
    }
  }

  /// Throws unless the response carries a successful code.
  Map<String, dynamic> expectOk(Map<String, dynamic> response, String path) {
    final rawCode = response['code'];
    // Some routes omit the code and rely on the HTTP status (already 2xx).
    final code = rawCode == null
        ? 200
        : JsonUtils.integer(rawCode, fallback: 200);
    if (code != 200) {
      throw BiliApiException(
        code: code,
        message: _errorMessage(code, response),
        path: path,
      );
    }
    return response;
  }

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
        message: '网易云接口响应格式异常',
        path: path,
      );
    }
    return body.map((key, value) => MapEntry('$key', value));
  }

  String _errorMessage(int code, Map<String, dynamic> response) {
    final upstream = JsonUtils.string(
      response['message'] ?? response['msg'] ?? response['error'],
    );
    const mapped = {
      301: '需要登录网易云账号',
      -460: '操作过于频繁，请稍后重试',
      400: '请求参数有误',
      404: '资源不存在或已被删除',
      502: '网易云接口暂时不可用，请稍后重试',
    };
    if (mapped.containsKey(code)) return mapped[code]!;
    if (upstream.isNotEmpty && upstream != '0') return upstream;
    return '网易云请求失败（$code）';
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
}
