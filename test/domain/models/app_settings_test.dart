import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/models/app_settings.dart';

void main() {
  group('PastCommentFetchCountValue.fromStorageValue', () {
    test('returns default count100 for unknown value', () {
      expect(
        PastCommentFetchCountValue.fromStorageValue('unexpected'),
        PastCommentFetchCount.count100,
      );
    });
  });

  group('PastCommentFetchCountValue.label', () {
    test('uses spec label for all option', () {
      expect(PastCommentFetchCount.all.label, '全部（上限あり）');
    });
  });

  group('AppSettings.copyWith', () {
    test('copies niconicoAccessToken', () {
      const AppSettings original = AppSettings.defaults;
      expect(original.niconicoAccessToken, '');

      final AppSettings updated =
          original.copyWith(niconicoAccessToken: 'my-token');
      expect(updated.niconicoAccessToken, 'my-token');
      expect(original.niconicoAccessToken, '');
    });

    test('preserves niconicoAccessToken when not overridden', () {
      final AppSettings withToken =
          AppSettings.defaults.copyWith(niconicoAccessToken: 'token-abc');
      final AppSettings copied = withToken.copyWith(debugMode: true);
      expect(copied.niconicoAccessToken, 'token-abc');
      expect(copied.debugMode, isTrue);
    });
  });
}
