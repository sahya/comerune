@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest.xml foreground service declaration', () {
    final File manifestFile = File('android/app/src/main/AndroidManifest.xml');
    late String manifestSource;

    setUpAll(() {
      manifestSource = manifestFile.readAsStringSync();
    });

    test('declares com.pravera.flutter_foreground_task ForegroundService with '
        'android:stopWithTask="true" so the notification is removed when the '
        'user swipes the app away from recents (issue #869)', () {
      final RegExp serviceBlock = RegExp(
        r'<service\b[^>]*android:name="com\.pravera\.flutter_foreground_task'
        r'\.service\.ForegroundService"[^>]*?/?>',
        dotAll: true,
      );
      final RegExpMatch? match = serviceBlock.firstMatch(manifestSource);
      expect(
        match,
        isNotNull,
        reason: 'ForegroundService declaration not found in $manifestFile',
      );
      expect(
        match!.group(0),
        contains('android:stopWithTask="true"'),
        reason:
            'Without android:stopWithTask="true" the foreground service '
            'notification persists after the user swipes the app away '
            'from the recents list. See issue #869.',
      );
    });
  });
}
