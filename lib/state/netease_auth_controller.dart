import 'dart:async';

import 'package:flowingpod/core/api/api_exception.dart';
import 'package:flowingpod/core/models/netease_user.dart';
import 'package:flowingpod/data/repositories/netease_repository.dart';
import 'package:flowingpod/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign-in status of the NetEase Cloud Music account.
class NeteaseAuthState {
  const NeteaseAuthState({
    this.initialized = false,
    this.loading = false,
    this.user,
    this.error,
  });

  final bool initialized;
  final bool loading;
  final NeteaseUser? user;
  final String? error;

  bool get isLoggedIn => user != null;

  NeteaseAuthState copyWith({
    bool? initialized,
    bool? loading,
    NeteaseUser? user,
    String? error,
    bool clearUser = false,
  }) => NeteaseAuthState(
    initialized: initialized ?? this.initialized,
    loading: loading ?? this.loading,
    user: clearUser ? null : (user ?? this.user),
    error: error,
  );
}

final NotifierProvider<NeteaseAuthController, NeteaseAuthState>
neteaseAuthProvider = NotifierProvider<NeteaseAuthController, NeteaseAuthState>(
  NeteaseAuthController.new,
);

class NeteaseAuthController extends Notifier<NeteaseAuthState> {
  @override
  NeteaseAuthState build() {
    Future.microtask(refresh);
    return const NeteaseAuthState();
  }

  NeteaseRepository get _repository => ref.read(neteaseRepositoryProvider);

  Future<void> refresh() async {
    if (!_repository.isLoggedIn) {
      if (ref.mounted) state = const NeteaseAuthState(initialized: true);
      return;
    }
    if (ref.mounted) {
      state = NeteaseAuthState(
        initialized: state.initialized,
        loading: true,
        user: state.user,
      );
    }
    try {
      final user = await _repository.fetchCurrentUser();
      if (ref.mounted) state = NeteaseAuthState(initialized: true, user: user);
    } on BiliApiException catch (error) {
      if (error.code == 301 || error.code == -101) {
        await _repository.logout();
        if (ref.mounted) state = const NeteaseAuthState(initialized: true);
        return;
      }
      if (ref.mounted) {
        state = NeteaseAuthState(
          initialized: true,
          user: state.user,
          error: error.message,
        );
      }
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    if (ref.mounted) state = const NeteaseAuthState(initialized: true);
  }
}

// --- QR login ---------------------------------------------------------------

enum NeteaseQrViewStatus { loading, waiting, scanned, expired, success, failed }

class NeteaseQrViewState {
  const NeteaseQrViewState({
    this.status = NeteaseQrViewStatus.loading,
    this.qrContent,
    this.message,
  });

  final NeteaseQrViewStatus status;
  final String? qrContent;
  final String? message;
}

final NotifierProvider<NeteaseQrController, NeteaseQrViewState>
neteaseQrProvider = NotifierProvider<NeteaseQrController, NeteaseQrViewState>(
  NeteaseQrController.new,
);

class NeteaseQrController extends Notifier<NeteaseQrViewState> {
  static const Duration _pollInterval = Duration(seconds: 2);

  Timer? _timer;
  String? _key;
  bool _polling = false;

  @override
  NeteaseQrViewState build() {
    ref.onDispose(() => _timer?.cancel());
    return const NeteaseQrViewState();
  }

  Future<void> start() async {
    _timer?.cancel();
    _polling = false;
    if (ref.mounted) state = const NeteaseQrViewState();
    try {
      final key = await ref.read(neteaseRepositoryProvider).createQrKey();
      final url = await ref.read(neteaseRepositoryProvider).createQrUrl(key);
      _key = key;
      if (!ref.mounted) return;
      state = NeteaseQrViewState(
        status: NeteaseQrViewStatus.waiting,
        qrContent: url,
      );
      _schedulePoll();
    } on BiliApiException catch (error) {
      if (ref.mounted) {
        state = NeteaseQrViewState(
          status: NeteaseQrViewStatus.failed,
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
      final result = await ref.read(neteaseRepositoryProvider).checkQr(key);
      if (!ref.mounted) return;
      switch (result.status) {
        case NeteaseQrStatus.waiting:
          state = NeteaseQrViewState(
            status: NeteaseQrViewStatus.waiting,
            qrContent: state.qrContent,
          );
          _schedulePoll();
        case NeteaseQrStatus.scanned:
          state = NeteaseQrViewState(
            status: NeteaseQrViewStatus.scanned,
            qrContent: state.qrContent,
          );
          _schedulePoll();
        case NeteaseQrStatus.expired:
          state = const NeteaseQrViewState(status: NeteaseQrViewStatus.expired);
        case NeteaseQrStatus.success:
          state = const NeteaseQrViewState(status: NeteaseQrViewStatus.success);
          await ref.read(neteaseAuthProvider.notifier).refresh();
        case NeteaseQrStatus.failed:
          state = NeteaseQrViewState(
            status: NeteaseQrViewStatus.failed,
            message: result.message,
          );
      }
    } on BiliApiException catch (error) {
      if (ref.mounted) {
        state = NeteaseQrViewState(
          status: NeteaseQrViewStatus.failed,
          message: error.message,
        );
      }
    } finally {
      _polling = false;
    }
  }
}

// --- Phone login ------------------------------------------------------------

class NeteaseSmsViewState {
  const NeteaseSmsViewState({
    this.phone = '',
    this.code = '',
    this.busy = false,
    this.codeSent = false,
    this.resendIn = 0,
    this.message,
    this.succeeded = false,
  });

  static final RegExp _mainlandPhone = RegExp(r'^1[3-9]\d{9}$');

  final String phone;
  final String code;
  final bool busy;
  final bool codeSent;
  final int resendIn;
  final String? message;
  final bool succeeded;

  bool get phoneValid => _mainlandPhone.hasMatch(phone);
  bool get canSendCode => !busy && resendIn == 0 && phoneValid;
  bool get canSubmit => !busy && codeSent && code.length == 4;

  NeteaseSmsViewState copyWith({
    String? phone,
    String? code,
    bool? busy,
    bool? codeSent,
    int? resendIn,
    String? message,
    bool clearMessage = false,
    bool? succeeded,
  }) => NeteaseSmsViewState(
    phone: phone ?? this.phone,
    code: code ?? this.code,
    busy: busy ?? this.busy,
    codeSent: codeSent ?? this.codeSent,
    resendIn: resendIn ?? this.resendIn,
    message: clearMessage ? null : (message ?? this.message),
    succeeded: succeeded ?? this.succeeded,
  );
}

final NotifierProvider<NeteaseSmsController, NeteaseSmsViewState>
neteaseSmsProvider =
    NotifierProvider<NeteaseSmsController, NeteaseSmsViewState>(
      NeteaseSmsController.new,
    );

class NeteaseSmsController extends Notifier<NeteaseSmsViewState> {
  static const int resendDelay = 60;

  Timer? _countdown;

  @override
  NeteaseSmsViewState build() {
    ref.onDispose(() => _countdown?.cancel());
    return const NeteaseSmsViewState();
  }

  void setPhone(String value) {
    if (state.phone != value) {
      _set(state.copyWith(phone: value, clearMessage: true));
    }
  }

  void setCode(String value) {
    if (state.code != value) {
      _set(state.copyWith(code: value, clearMessage: true));
    }
  }

  void reset() {
    _countdown?.cancel();
    _set(const NeteaseSmsViewState());
  }

  Future<bool> sendCode() async {
    if (!state.phoneValid) {
      _set(state.copyWith(message: '请输入正确的手机号'));
      return false;
    }
    _set(state.copyWith(busy: true, clearMessage: true));
    try {
      await ref.read(neteaseRepositoryProvider).sendSmsCode(state.phone);
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

  Future<bool> submit() async {
    _set(state.copyWith(busy: true, clearMessage: true));
    try {
      await ref
          .read(neteaseRepositoryProvider)
          .loginWithSmsCode(phone: state.phone, code: state.code);
      await ref.read(neteaseAuthProvider.notifier).refresh();
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

  void _set(NeteaseSmsViewState next) {
    if (ref.mounted) state = next;
  }
}
