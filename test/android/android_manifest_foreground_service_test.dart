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

  group('AndroidManifest.xml App Links callback handling', () {
    final File manifestFile = File('android/app/src/main/AndroidManifest.xml');
    late String mainActivitySource;

    setUpAll(() {
      // XML comments are stripped first so a commented-out declaration
      // does not satisfy the assertion below.
      final String manifestSource = manifestFile.readAsStringSync().replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );
      // Captures the whole MainActivity element (opening tag through
      // </activity>) so the assertion below only passes when the meta-data
      // sits inside the activity. Flutter reads this flag from the
      // activity's own meta-data, not from <application>.
      final RegExp mainActivity = RegExp(
        r'<activity\b[^>]*android:name="\.MainActivity".*?</activity>',
        dotAll: true,
      );
      final RegExpMatch? match = mainActivity.firstMatch(manifestSource);
      if (match == null) {
        fail('MainActivity declaration not found in $manifestFile');
      }
      mainActivitySource = match.group(0)!;
    });

    test('disables Flutter built-in deep linking on MainActivity so the OAuth '
        'callback URL is handled only by app_links', () {
      // Without this flag the Flutter embedding also hands incoming VIEW
      // intent URLs to the Navigator: as the initial route on cold start
      // (silently dropped, since it does not start with "/"), and via
      // pushRouteInformation on warm start. The app has no route for the
      // callback, so in debug builds the warm-start path throws a routing
      // error whose message includes the callback path and query
      // (authorization code and state). The app_links Android setup asks
      // for the flag to be disabled explicitly.
      //
      // Attribute order and self-closing vs. open form are not fixed, so
      // each <meta-data> start tag is checked for both attributes.
      final Iterable<String> metaDataTags = RegExp(
        r'<meta-data\b[^>]*>',
      ).allMatches(mainActivitySource).map((RegExpMatch m) => m.group(0)!);
      final bool hasFlag = metaDataTags.any(
        (String tag) =>
            tag.contains('android:name="flutter_deeplinking_enabled"') &&
            tag.contains('android:value="false"'),
      );
      expect(
        hasFlag,
        isTrue,
        reason:
            'MainActivity must declare <meta-data '
            'android:name="flutter_deeplinking_enabled" '
            'android:value="false" /> so the OAuth callback URL is not '
            'pushed to the Navigator.',
      );
    });
  });
}
