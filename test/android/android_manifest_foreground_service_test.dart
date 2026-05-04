@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidManifest.xml foreground service declaration', () {
    final File manifestFile = File('android/app/src/main/AndroidManifest.xml');
    late String serviceTagSource;

    setUpAll(() {
      final String manifestSource = manifestFile.readAsStringSync();
      // Captures the opening <service ...> tag of the flutter_foreground_task
      // service. Both the self-closing form (current) and the open form
      // (`<service ... >...</service>`) are supported so future child-element
      // additions don't silently bypass the assertions below.
      final RegExp serviceTag = RegExp(
        r'<service\b[^>]*android:name="com\.pravera\.flutter_foreground_task'
        r'\.service\.ForegroundService"[^>]*?/?>',
        dotAll: true,
      );
      final RegExpMatch? match = serviceTag.firstMatch(manifestSource);
      if (match == null) {
        fail(
          'flutter_foreground_task ForegroundService declaration not found '
          'in $manifestFile',
        );
      }
      serviceTagSource = match.group(0)!;
    });

    test('sets android:stopWithTask="true" so the notification disappears when '
        'the user swipes the app away from recents (issue #869)', () {
      expect(
        serviceTagSource,
        contains('android:stopWithTask="true"'),
        reason:
            'Without android:stopWithTask="true" the foreground service '
            'notification persists after the user swipes the app away '
            'from the recents list. See issue #869.',
      );
    });

    test(
      'sets android:foregroundServiceType="dataSync" so Android 14+ does not '
      'revoke the foreground service mid-streaming',
      () {
        // dataSync matches the actual workload (keeping a comment streaming
        // connection alive). mediaPlayback would risk Android 14+ revocation
        // since no media is continuously played. Asserted alongside
        // stopWithTask because both attributes live on the same <service>
        // element and a typo on either silently breaks the FGS notification
        // contract.
        expect(
          serviceTagSource,
          contains('android:foregroundServiceType="dataSync"'),
          reason:
              'foregroundServiceType="dataSync" is required for the comment '
              'streaming foreground service on Android 10+.',
        );
      },
    );

    test('keeps android:exported="false" so external apps cannot bind to the '
        'foreground service', () {
      // An exported foreground service can be bound by other apps via
      // bindService(), opening up lifecycle hijacking and IPC-based
      // information leakage. The current value is correct; this assertion
      // exists purely as a regression guard for future manifest edits.
      expect(
        serviceTagSource,
        contains('android:exported="false"'),
        reason:
            'android:exported="false" is required so external apps cannot '
            'bind to or hijack the comment streaming foreground service.',
      );
    });
  });
}
