import 'package:flowingpod/core/api/wbi_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imgKey = '7cd084941338484aae1ad9425b84077c';
  const subKey = '4932caff0ff746eab6f01bf08b70ac45';

  group('WbiSigner', () {
    test('derives the mixin key from the documented example', () {
      // Example from docs/misc/sign/wbi.md.
      expect(
        WbiSigner.mixinKey('$imgKey$subKey'),
        'ea1db124af3c7062474693fa704f4ff8',
      );
    });

    test('takes the first 32 characters of the permuted key', () {
      expect(WbiSigner.mixinKey('$imgKey$subKey').length, 32);
    });

    test('adds wts and a 32 character w_rid', () {
      final signed = WbiSigner(
        imgKey: imgKey,
        subKey: subKey,
      ).sign({'bvid': 'BV1rp4y1e745', 'cid': 244954665, 'fnval': 4048});

      expect(signed['wts'], isNotNull);
      expect(int.tryParse(signed['wts']!), isNotNull);
      expect(signed['w_rid'], hasLength(32));
      expect(signed['cid'], '244954665');
      expect(signed.keys, containsAll(['bvid', 'cid', 'fnval', 'wts', 'w_rid']));
    });

    test('strips reserved characters so the sent query matches the signature', () {
      final signed = WbiSigner(
        imgKey: imgKey,
        subKey: subKey,
      ).sign({'keyword': "a!b'c(d)e*f"});

      // `Uri.encodeComponent` leaves these characters untouched, so they must
      // be removed before signing and before building the request URL.
      expect(signed['keyword'], 'abcdef');
    });

    test('ignores null parameters', () {
      final signed = WbiSigner(imgKey: imgKey, subKey: subKey).sign({
        'bvid': 'BV1',
        'keyword': null,
      });
      expect(signed.containsKey('keyword'), isFalse);
    });

    test('produces a stable signature for fixed inputs', () {
      final signer = WbiSigner(imgKey: imgKey, subKey: subKey);
      expect(signer.sign({'cid': 1})['w_rid'], signer.sign({'cid': 1})['w_rid']);
    });
  });
}
