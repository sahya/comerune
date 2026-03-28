import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/models/app_settings.dart';

void main() {
  group('AppThemeModeValue.fromStorageValue', () {
    test('returns light for null', () {
      expect(
        AppThemeModeValue.fromStorageValue(null),
        AppThemeMode.light,
      );
    });

    test('returns light for unknown value', () {
      expect(
        AppThemeModeValue.fromStorageValue('garbage'),
        AppThemeMode.light,
      );
    });

    test('returns light for empty string', () {
      expect(
        AppThemeModeValue.fromStorageValue(''),
        AppThemeMode.light,
      );
    });

    test('round-trips all enum values via storageValue', () {
      for (final AppThemeMode mode in AppThemeMode.values) {
        expect(
          AppThemeModeValue.fromStorageValue(mode.storageValue),
          mode,
        );
      }
    });
  });

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

  group('ngUserIdSet', () {
    test('returns empty set for empty string', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.ngUserIdSet, isEmpty);
    });

    test('parses newline-separated user IDs', () {
      final AppSettings settings =
          AppSettings.defaults.copyWith(ngUserIds: '123\n456\n789');
      expect(settings.ngUserIdSet, <String>{'123', '456', '789'});
    });

    test('trims whitespace and ignores blank lines', () {
      final AppSettings settings =
          AppSettings.defaults.copyWith(ngUserIds: ' 123 \n\n 456 \n');
      expect(settings.ngUserIdSet, <String>{'123', '456'});
    });
  });

  group('isNgUser', () {
    test('returns false for null userId', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.isNgUser(null), isFalse);
    });

    test('returns true for registered NG user', () {
      final AppSettings settings =
          AppSettings.defaults.copyWith(ngUserIds: '123\n456');
      expect(settings.isNgUser('123'), isTrue);
      expect(settings.isNgUser('456'), isTrue);
      expect(settings.isNgUser('789'), isFalse);
    });
  });

  group('addNgUserId', () {
    test('adds new user ID', () {
      final AppSettings updated = AppSettings.defaults.addNgUserId('123');
      expect(updated.ngUserIdSet, <String>{'123'});
    });

    test('does not duplicate existing ID', () {
      final AppSettings initial =
          AppSettings.defaults.copyWith(ngUserIds: '123');
      final AppSettings updated = initial.addNgUserId('123');
      expect(identical(updated, initial), isTrue);
    });
  });

  group('removeNgUserId', () {
    test('removes existing user ID', () {
      final AppSettings initial =
          AppSettings.defaults.copyWith(ngUserIds: '123\n456');
      final AppSettings updated = initial.removeNgUserId('123');
      expect(updated.ngUserIdSet, <String>{'456'});
    });

    test('returns same instance if ID not present', () {
      final AppSettings initial =
          AppSettings.defaults.copyWith(ngUserIds: '123');
      final AppSettings updated = initial.removeNgUserId('999');
      expect(identical(updated, initial), isTrue);
    });
  });
}
