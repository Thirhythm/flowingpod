import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

/// Port of the NetEase web API encryption (``weapi``).
///
/// The parameters are AES-CBC encrypted twice and the random secret is RSA
/// encrypted with the fixed public key used by the web player.
abstract final class NeteaseCrypto {
  static const String _iv = '0102030405060708';
  static const String _presetKey = '0CoJUm6Qyw8W8jud';
  static const String _base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static const String _modulusHex =
      'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b7251'
      '52b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312e'
      'cbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b42'
      '4d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a2'
      '2b8e7';

  static const int _exponent = 0x10001;

  static final BigInt _modulus = BigInt.parse(_modulusHex, radix: 16);
  static final Random _random = Random.secure();

  /// Encrypts [data] into the `params` / `encSecKey` form fields.
  static Map<String, String> weapi(Map<String, Object?> data) {
    final text = jsonEncode(data);
    final secret = _secretKey();
    return {
      'params': _aesEncrypt(_aesEncrypt(text, _presetKey), secret),
      'encSecKey': _rsaEncrypt(_reverse(secret)),
    };
  }

  static String _secretKey() => [
    for (var index = 0; index < 16; index++)
      _base62[_random.nextInt(_base62.length)],
  ].join();

  static String _reverse(String value) => value.split('').reversed.join();

  static String _aesEncrypt(String text, String key) {
    final data = utf8.encode(text);
    final padding = 16 - data.length % 16;
    final padded = Uint8List(data.length + padding)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + padding, padding);

    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        true,
        ParametersWithIV<KeyParameter>(
          KeyParameter(utf8.encode(key)),
          utf8.encode(_iv),
        ),
      );

    final output = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, output, offset);
    }
    return base64Encode(output);
  }

  static String _rsaEncrypt(String text) {
    var message = BigInt.zero;
    for (final byte in utf8.encode(text)) {
      message = (message << 8) | BigInt.from(byte);
    }
    return message
        .modPow(BigInt.from(_exponent), _modulus)
        .toRadixString(16)
        .padLeft(256, '0');
  }
}
