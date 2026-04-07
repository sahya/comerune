import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('debug log policy', () {
    test('high-frequency files avoid interpolated direct appDebugLog calls',
        () {
      const List<String> targets = <String>[
        'lib/data/follow/my_program_repository.dart',
        'lib/data/follow/favorite_user_live_checker.dart',
      ];

      final RegExp directInterpolatedDebugLog = RegExp(
        r'appDebugLog\([^)]*\$',
        multiLine: true,
      );

      for (final String path in targets) {
        final String content = File(path).readAsStringSync();
        expect(
          directInterpolatedDebugLog.hasMatch(content),
          isFalse,
          reason:
              'Use appDebugLogLazy for interpolated messages in high-frequency file: $path',
        );
      }
    });

    test('select screen avoids interpolated _debugLog wrapper calls', () {
      const String path = 'lib/presentation/select/select_screen.dart';
      final String content = File(path).readAsStringSync();
      final RegExp interpolatedWrapperCall = RegExp(
        r'_debugLog\([^)]*\$',
        multiLine: true,
      );

      expect(
        interpolatedWrapperCall.hasMatch(content),
        isFalse,
        reason:
            'Use _debugLogLazy for interpolated messages in SelectScreen high-frequency logs',
      );
    });
  });
}
