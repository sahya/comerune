import 'package:comerune/app_logging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app logging', () {
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      originalDebugPrint = debugPrint;
      debugPrint = (String? _, {int? wrapWidth}) {};
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('appDebugLogLazy evaluates message builder in debug build', () {
      int called = 0;

      appDebugLogLazy(() {
        called += 1;
        return 'lazy debug message';
      });

      expect(called, kDebugMode ? 1 : 0);
    });

    test('appDebugLog writes one line in debug build', () {
      int printed = 0;
      debugPrint = (String? _, {int? wrapWidth}) {
        printed += 1;
      };

      appDebugLog('plain debug message');

      expect(printed, kDebugMode ? 1 : 0);
    });
  });
}
