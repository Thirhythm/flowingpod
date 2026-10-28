import 'dart:async';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/bili_user.dart';
import 'package:flowingpod/data/repositories/auth_repository.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign-in status of the Bilibili account.
class AuthState {
  const AuthState({
    this.initialized = false,
    this.loading = false,
    this.user,
    this.error,
  });

  final bool initialized;
  final bool loading;
  final BiliUser? user;
  final String? error;

  bool get isLoggedIn => user != null;

  AuthState copyWith({
    bool? initialized,
    bool? loading,
    BiliUser? user,
    String? error,
    bool clearUser = false,
  }) => AuthState(
    initialized: initialized ?? this.initialized,
    loading: loading ?? this.loading,
    user: clearUser ? null : (user ?? this.user),
    error: error,
  );
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Owns the account session and exposes it to the rest of the app.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(refresh);
    return const AuthState();
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Reloads the account information from the API.
  Future<void> refresh() async {
    if (!_repository.isLoggedIn) {
      if (ref.mounted) state = const AuthState(initialized: true);
      return;
    }
    if (ref.mounted) {
      state = AuthState(
        initialized: state.initialized,
        loading: true,
        user: state.user,
      );
    }
    try {
      final user = await _repository.fetchCurrentUser();
      if (ref.mounted) state = AuthState(initialized: true, user: user);
    } on BiliApiException catch (error) {
      if (ref.mounted) {
        state = AuthState(
          initialized: true,
          user: state.user,
          error: error.message,
        );
      }
    }
  }

  /// Clears the session both locally and on the server.
  Future<void> logout() async {
    await _repository.logout();
    if (ref.mounted) state = const AuthState(initialized: true);
  }
}

/// International dialling code used by the phone login. Only mainland China
/// is supported, matching the web login page's default.
const String smsDialCode = '86';

/// Phone-login form state.
class SmsLoginViewState {
  const SmsLoginViewState({
    this.tel = '',
    this.code = '',
    this.busy = false,
    this.codeSent = false,
    this.resendIn = 0,
    this.captcha,
    this.message,
    this.succeeded = false,
  });

  /// Mainland numbers only: `1` followed by ten more digits.
  static final RegExp _mainlandTel = RegExp(r'^1[3-9]\d{9}$');

  /// Number typed by the user, without the dialling code.
  final String tel;

  /// SMS code typed by the user.
  final String code;

  /// `true` while a code request or the login itself is in flight.
  final bool busy;

  /// `true` once an SMS code has been sent successfully.
  final bool codeSent;

  /// Seconds left before the code may be requested again.
  final int resendIn;

  /// Challenge the user is currently solving, when the captcha is on screen.
  final CaptchaChallenge? captcha;

  /// Error or hint shown under the form.
  final String? message;

  /// `true` once the session has been established.
  final bool succeeded;

  bool get telValid => _mainlandTel.hasMatch(tel);

  bool get canSendCode =>
      !busy && captcha == null && resendIn == 0 && telValid;

  bool get canSubmit => !busy && codeSent && code.length == 6;

  SmsLoginViewState copyWith({
    String? tel,
    String? code,
    bool? busy,
    bool? codeSent,
    int? resendIn,
    CaptchaChallenge? captcha,
    bool clearCaptcha = false,
    String? message,
    bool clearMessage = false,
    bool? succeeded,
  }) => SmsLoginViewState(
    tel: tel ?? this.tel,
    code: code ?? this.code,
    busy: busy ?? this.busy,
    codeSent: codeSent ?? this.codeSent,
    resendIn: resendIn ?? this.resendIn,
    captcha: clearCaptcha ? null : (captcha ?? this.captcha),
    message: clearMessage ? null : (message ?? this.message),
    succeeded: succeeded ?? this.succeeded,
  );
}

final NotifierProvider<SmsLoginController, SmsLoginViewState> smsLoginProvider =
    NotifierProvider<SmsLoginController, SmsLoginViewState>(
      SmsLoginController.new,
    );

/// Drives phone login: geetest challenge → SMS code → session.
class SmsLoginController extends Notifier<SmsLoginViewState> {
  /// Seconds the resend action stays disabled, matching the web login page.
  static const int resendDelay = 60;

  Timer? _countdown;
  String? _captchaKey;

  @override
  SmsLoginViewState build() {
    ref.onDispose(() => _countdown?.cancel());
    return const SmsLoginViewState();
  }

  void setTel(String value) {
    if (state.tel != value) {
      _set(state.copyWith(tel: value, clearMessage: true));
    }
  }

  void setCode(String value) {
    if (state.code != value) {
      _set(state.copyWith(code: value, clearMessage: true));
    }
  }

  /// Drops any previous attempt; called when the login page is opened.
  void reset() {
    _countdown?.cancel();
    _captchaKey = null;
    _set(const SmsLoginViewState());
  }

  /// Requests the geetest parameters and shows the captcha widget.
  ///
  /// Returns `false` after reporting the failure on [state].
  Future<bool> startCaptcha() async {
    _set(state.copyWith(busy: true, clearMessage: true, clearCaptcha: true));
    try {
      final challenge = await ref.read(authRepositoryProvider).createCaptcha();
      _set(state.copyWith(busy: false, captcha: challenge));
      return true;
    } on BiliApiException catch (error) {
      _set(state.copyWith(busy: false, message: error.message));
      return false;
    }
  }

  /// Hides the captcha, optionally reporting why it did not complete.
  void endCaptcha({String? error}) {
    _set(
      state.copyWith(
        busy: false,
        clearCaptcha: true,
        message: error,
        clearMessage: error == null,
      ),
    );
  }

  /// Sends the SMS code using a solved geetest challenge.
  Future<bool> sendCode({
    required CaptchaChallenge captcha,
    required String challenge,
    required String validate,
    required String seccode,
  }) async {
    _set(
      state.copyWith(
        busy: true,
        clearCaptcha: true,
        clearMessage: true,
      ),
    );
    try {
      final key = await ref.read(authRepositoryProvider).sendSmsCode(
        cid: smsDialCode,
        tel: state.tel,
        captcha: captcha,
        challenge: challenge,
        validate: validate,
        seccode: seccode,
      );
      _captchaKey = key;
      _set(
        state.copyWith(
          busy: false,
          codeSent: true,
          resendIn: resendDelay,
          clearMessage: true,
        ),
      );
      _startCountdown();
      return true;
    } on BiliApiException catch (error) {
      _set(state.copyWith(busy: false, message: error.message));
      return false;
    }
  }

  /// Submits the SMS code and reloads the account on success.
  Future<bool> submitCode() async {
    final key = _captchaKey;
    if (key == null) {
      _set(state.copyWith(message: '请先获取短信验证码'));
      return false;
    }
    _set(state.copyWith(busy: true, clearMessage: true));
    try {
      await ref.read(authRepositoryProvider).loginWithSmsCode(
        cid: smsDialCode,
        tel: state.tel,
        code: state.code,
        captchaKey: key,
      );
      await ref.read(authControllerProvider.notifier).refresh();
      _set(state.copyWith(busy: false, succeeded: true, clearMessage: true));
      return true;
    } on BiliApiException catch (error) {
      _set(state.copyWith(busy: false, message: error.message));
      return false;
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!ref.mounted) {
        timer.cancel();
        return;
      }
      final remaining = state.resendIn - 1;
      if (remaining <= 0) {
        timer.cancel();
        _set(state.copyWith(resendIn: 0));
      } else {
        _set(state.copyWith(resendIn: remaining));
      }
    });
  }

  /// Publishes [next] unless the controller has been disposed meanwhile.
  void _set(SmsLoginViewState next) {
    if (ref.mounted) state = next;
  }
}

/// Steps of the QR login flow shown by the login page.
enum QrStatus { loading, waiting, scanned, expired, success, failed }

class QrLoginViewState {
  const QrLoginViewState({
    this.status = QrStatus.loading,
    this.qrContent,
    this.message,
  });

  final QrStatus status;

  /// Content to render as a QR code.
  final String? qrContent;
  final String? message;
}

// Auto-disposed so the 2 second poll stops as soon as the login page is gone;
// otherwise the timer would keep hitting the passport API for the whole session.
final NotifierProvider<QrLoginController, QrLoginViewState> qrLoginProvider =
    NotifierProvider<QrLoginController, QrLoginViewState>(
      QrLoginController.new,
      isAutoDispose: true,
    );

/// Drives the QR code login: creates a code and polls until it is confirmed.
class QrLoginController extends Notifier<QrLoginViewState> {
  static const Duration _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  String? _key;
  bool _polling = false;

  @override
  QrLoginViewState build() {
    ref.onDispose(() => _timer?.cancel());
    Future.microtask(start);
    return const QrLoginViewState();
  }

  /// Requests a new QR code (also used by the "refresh" button).
  Future<void> start() async {
    _timer?.cancel();
    _polling = false;
    // The provider is auto-disposed; the page may be gone before this runs.
    if (!ref.mounted) return;
    state = const QrLoginViewState();
    try {
      final session = await ref.read(authRepositoryProvider).createQrSession();
      _key = session.key;
      if (!ref.mounted) return;
      state = QrLoginViewState(
        status: QrStatus.waiting,
        qrContent: session.url,
      );
      _schedulePoll();
    } on BiliApiException catch (error) {
      if (ref.mounted) {
        state = QrLoginViewState(
          status: QrStatus.failed,
          message: error.message,
        );
      }
    }
  }

  void _schedulePoll() {
    _timer?.cancel();
    _timer = Timer(_pollInterval, _poll);
  }

  Future<void> _poll() async {
    final key = _key;
    if (key == null || _polling || !ref.mounted) return;
    _polling = true;
    try {
      final result = await ref.read(authRepositoryProvider).pollQrSession(key);
      if (!ref.mounted) return;
      switch (result.status) {
        case QrLoginStatus.waiting:
          state = QrLoginViewState(
            status: QrStatus.waiting,
            qrContent: state.qrContent,
          );
          _schedulePoll();
        case QrLoginStatus.scanned:
          state = QrLoginViewState(
            status: QrStatus.scanned,
            qrContent: state.qrContent,
          );
          _schedulePoll();
        case QrLoginStatus.expired:
          state = const QrLoginViewState(status: QrStatus.expired);
        case QrLoginStatus.success:
          state = const QrLoginViewState(status: QrStatus.success);
          await ref.read(authControllerProvider.notifier).refresh();
        case QrLoginStatus.failed:
          state = QrLoginViewState(
            status: QrStatus.failed,
            message: result.message,
          );
      }
    } on BiliApiException catch (error) {
      if (ref.mounted) {
        state = QrLoginViewState(status: QrStatus.failed, message: error.message);
      }
    } finally {
      _polling = false;
    }
  }
}
