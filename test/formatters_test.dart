import 'package:flowingpod/core/utils/formatters.dart';
import 'package:flowingpod/core/utils/text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters.duration', () {
    test('formats minutes and seconds', () {
      expect(Formatters.duration(Duration.zero), '00:00');
      expect(Formatters.duration(const Duration(seconds: 59)), '00:59');
      expect(
        Formatters.duration(const Duration(minutes: 3, seconds: 7)),
        '03:07',
      );
    });

    test('formats hours', () {
      expect(
        Formatters.duration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('clamps negative durations', () {
      expect(Formatters.duration(const Duration(seconds: -5)), '00:00');
    });
  });

  group('Formatters.count', () {
    test('uses Chinese units', () {
      expect(Formatters.count(999), '999');
      expect(Formatters.count(12000), '1.2万');
      expect(Formatters.count(150000000), '1.5亿');
    });
  });

  group('TextUtils.stripHtml', () {
    test('removes search highlight markup and entities', () {
      expect(
        TextUtils.stripHtml('五月天<em class="keyword">温柔</em> &amp; 拥抱'),
        '五月天温柔 & 拥抱',
      );
    });
  });
}
