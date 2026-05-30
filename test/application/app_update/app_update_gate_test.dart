import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/app_update/app_update_gate.dart';

void main() {
  group('isAppUpdateAllowedForInstaller', () {
    test('null installerStore is allowed (treated as sideload)', () {
      expect(isAppUpdateAllowedForInstaller(null), isTrue);
    });

    test('empty installerStore is allowed', () {
      expect(isAppUpdateAllowedForInstaller(''), isTrue);
    });

    test('Google Play installer is denied', () {
      expect(isAppUpdateAllowedForInstaller('com.android.vending'), isFalse);
    });

    test('Google Play legacy feedback package is denied', () {
      expect(
        isAppUpdateAllowedForInstaller('com.google.android.feedback'),
        isFalse,
      );
    });

    test('Amazon Appstore is denied', () {
      expect(isAppUpdateAllowedForInstaller('com.amazon.venezia'), isFalse);
    });

    test('F-Droid (and privileged extension) are denied', () {
      expect(isAppUpdateAllowedForInstaller('org.fdroid.fdroid'), isFalse);
      expect(
        isAppUpdateAllowedForInstaller('org.fdroid.fdroid.privileged'),
        isFalse,
      );
    });

    test('Samsung Galaxy Store is denied', () {
      expect(
        isAppUpdateAllowedForInstaller('com.sec.android.app.samsungapps'),
        isFalse,
      );
    });

    test('Huawei AppGallery is denied', () {
      expect(isAppUpdateAllowedForInstaller('com.huawei.appmarket'), isFalse);
    });

    test('adb shell installer is allowed (dev install)', () {
      expect(isAppUpdateAllowedForInstaller('com.android.shell'), isTrue);
    });

    test('arbitrary unknown installer is allowed (assume sideload)', () {
      expect(
        isAppUpdateAllowedForInstaller('com.example.unknownsideloader'),
        isTrue,
      );
    });

    test('exact match required — partial substring is allowed', () {
      // 部分一致で誤判定しないことを確認する。
      expect(
        isAppUpdateAllowedForInstaller('com.android.vending.imposter'),
        isTrue,
      );
    });
  });
}
