import 'dart:convert';

import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Solution produced by a solved geetest challenge.
class GeetestResult {
  const GeetestResult({
    required this.challenge,
    required this.validate,
    required this.seccode,
  });

  /// Challenge the solution belongs to; geetest issues a new one per attempt.
  final String challenge;
  final String validate;
  final String seccode;
}

/// How the login page reacts to the captcha widget.
class GeetestCallbacks {
  const GeetestCallbacks({
    required this.onSolved,
    required this.onClosed,
    required this.onFailed,
  });

  /// The challenge was solved.
  final ValueChanged<GeetestResult> onSolved;

  /// The user dismissed the widget.
  final VoidCallback onClosed;

  /// The widget could not run, so the attempt has to be restarted.
  final ValueChanged<String> onFailed;
}

/// Builds the captcha host shown inside the login page.
typedef CaptchaBuilder =
    Widget Function(CaptchaChallenge challenge, GeetestCallbacks callbacks);

/// Default [CaptchaBuilder]: the real geetest widget.
Widget buildGeetestView(
  CaptchaChallenge challenge,
  GeetestCallbacks callbacks,
) => GeetestView(challenge: challenge, callbacks: callbacks);

/// Runs the geetest widget in an inline WebView.
///
/// Bilibili refuses to send an SMS code unless the request carries a solved
/// geetest challenge, so the official SDK is hosted here instead of being
/// reimplemented. The widget reports through [GeetestCallbacks] rather than
/// navigating itself, which keeps it inside the login page.
class GeetestView extends StatefulWidget {
  const GeetestView({
    super.key,
    required this.challenge,
    required this.callbacks,
  });

  final CaptchaChallenge challenge;
  final GeetestCallbacks callbacks;

  @override
  State<GeetestView> createState() => _GeetestViewState();
}

class _GeetestViewState extends State<GeetestView> {
  /// Name of the JS bridge the widget reports through.
  static const String _bridge = 'GeetestBridge';

  /// The inline document is loaded under the SDK's own origin, so a script in
  /// it cannot reach passport.bilibili.com's same-origin endpoints.
  static const String _baseUrl = 'https://static.geetest.com/';

  /// Bridge messages only ever carry a few short geetest fields.
  static const int _maxMessageLength = 8192;
  static const int _maxFieldLength = 2048;

  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'about') return NavigationDecision.navigate;
            if (uri.scheme == 'https' &&
                (_isGeetestHost(uri.host) || _isBilibiliHost(uri.host))) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(_bridge, onMessageReceived: _onMessage)
      ..loadHtmlString(
        _buildHtml(widget.challenge.gt, widget.challenge.challenge),
        baseUrl: _baseUrl,
      );
  }

  static bool _isGeetestHost(String host) =>
      host == 'geetest.com' || host.endsWith('.geetest.com');

  static bool _isBilibiliHost(String host) =>
      host == 'bilibili.com' || host.endsWith('.bilibili.com');

  void _onMessage(JavaScriptMessage message) {
    // The page keeps reporting after the view has been removed.
    if (!mounted) return;
    if (message.message.length > _maxMessageLength) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final payload = decoded.map((key, value) => MapEntry('$key', value));

    if (payload['ready'] != null) {
      setState(() => _ready = true);
      return;
    }
    if (payload['closed'] != null) {
      widget.callbacks.onClosed();
      return;
    }
    if (payload['error'] != null) {
      widget.callbacks.onFailed('人机验证加载失败，请重试');
      return;
    }
    final validate = _stringField(payload['validate']);
    final seccode = _stringField(payload['seccode']);
    if (validate.isEmpty || seccode.isEmpty) return;
    widget.callbacks.onSolved(
      GeetestResult(
        challenge: _stringField(
          payload['challenge'],
          fallback: widget.challenge.challenge,
        ),
        validate: validate,
        seccode: seccode,
      ),
    );
  }

  static String _stringField(Object? value, {String fallback = ''}) {
    if (value is! String || value.isEmpty || value.length > _maxFieldLength) {
      return fallback;
    }
    return value;
  }

  /// Emits a JS string literal whose contents cannot close the enclosing
  /// `<script>` element.
  static String _jsString(String value) =>
      jsonEncode(value).replaceAll('<', r'\u003c');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_ready)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 12),
                    Text('正在加载人机验证…'),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Hosts the geetest SDK; `https` is set explicitly because the document is
  /// loaded from an inline string and has no meaningful page protocol.
  static String _buildHtml(String gt, String challenge) => '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body { margin: 0; padding: 0; background: #ffffff; overflow: hidden; }
</style>
<script src="https://static.geetest.com/static/js/gt.0.4.9.js"></script>
</head>
<body>
<script>
  function report(payload) {
    $_bridge.postMessage(JSON.stringify(payload));
  }
  window.onerror = function () {
    report({ error: 'script' });
  };
  window.onload = function () {
    if (typeof initGeetest !== 'function') {
      report({ error: 'sdk' });
      return;
    }
    initGeetest({
      gt: ${_jsString(gt)},
      challenge: ${_jsString(challenge)},
      offline: false,
      new_captcha: true,
      https: true,
      product: 'bind',
      width: '100%',
      lang: 'zh-cn'
    }, function (captcha) {
      // `bind` keeps the panel hidden until `verify()` is called.
      captcha.onReady(function () {
        report({ ready: true });
        captcha.verify();
      });
      captcha.onClose(function () {
        report({ closed: true });
      });
      captcha.onSuccess(function () {
        var result = captcha.getValidate();
        if (!result) {
          report({ error: 'validate' });
          return;
        }
        report({
          challenge: result.geetest_challenge,
          validate: result.geetest_validate,
          seccode: result.geetest_seccode
        });
      });
      captcha.onError(function () {
        report({ error: 'captcha' });
      });
    });
  };
</script>
</body>
</html>
''';
}
