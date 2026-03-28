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

}
