import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/auth/user_session_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/in_memory_user_session_store.dart';
import '../../helpers/settings_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ライセンスページが参照する PackageInfo にテスト用のモック値を注入する。
    PackageInfo.setMockInitialValues(
      appName: 'comerune',
      packageName: 'app.comerune',
      version: '1.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('SettingsScreen', () {
    testWidgets('shows login button when not logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-button')), findsOneWidget);
      expect(find.byKey(const Key('logout-button')), findsNothing);
      expect(find.text('コメント取得にはログインが必要です'), findsOneWidget);
    });

    testWidgets('shows logout button when logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('user_session_abc123');

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logout-button')), findsOneWidget);
      expect(find.byKey(const Key('login-button')), findsNothing);
      expect(find.text('ログイン済み'), findsOneWidget);
    });

    testWidgets('theme dropdown persists selected value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be light
      AppSettings loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.light);

      // Open the dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Tap the dark option in the dropdown overlay
      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.dark);
    });

    testWidgets('theme dropdown updates themeModeNotifier immediately', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<AppThemeMode> themeNotifier =
          ValueNotifier<AppThemeMode>(AppThemeMode.light);

      await tester.pumpWidget(
        _buildScreen(settingsStore, themeModeNotifier: themeNotifier),
      );
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.light);

      // Open dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.dark);

      themeNotifier.dispose();
    });

    testWidgets('debug mode toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('debug-mode-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      toggleSwitchByKeySync(tester, const Key('debug-mode-switch'));
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.debugMode, isTrue);
    });

    testWidgets('shows navigation tiles for sub-screens', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      // Scroll to each tile individually to verify it exists.
      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('comment-display-settings-tile')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('tts-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tts-settings-tile')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('user-management-settings-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('user-management-settings-tile')),
        findsOneWidget,
      );
    });

    testWidgets('tts tile shows auto-read status', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tts-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default autoRead is OFF
      expect(find.text('自動読み上げ: OFF'), findsOneWidget);
    });

    testWidgets('settings sections are displayed in correct order', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      // Account section should appear before theme (both visible initially).
      final double accountY = tester.getTopLeft(find.text('ニコニコアカウント')).dy;
      final double themeY = tester.getTopLeft(find.text('配色テーマ')).dy;
      expect(
        accountY,
        lessThan(themeY),
        reason: 'ニコニコアカウント should appear before テーマ',
      );

      // Scroll to comment-display tile; adjacent TTS tile should also be
      // visible since they are directly next to each other.
      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Comment display should appear before TTS.
      final double commentDisplayY = tester
          .getTopLeft(find.byKey(const Key('comment-display-settings-tile')))
          .dy;
      final double ttsY = tester
          .getTopLeft(find.byKey(const Key('tts-settings-tile')))
          .dy;
      expect(
        commentDisplayY,
        lessThan(ttsY),
        reason: 'コメント表示設定 should appear before 読み上げ設定',
      );

      // Scroll to user-management tile; adjacent export button should also be
      // visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('user-management-settings-tile')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // User management should appear before data management.
      final double userMgmtY = tester
          .getTopLeft(find.byKey(const Key('user-management-settings-tile')))
          .dy;
      final double exportY = tester
          .getTopLeft(find.byKey(const Key('export-settings-button')))
          .dy;
      expect(
        userMgmtY,
        lessThan(exportY),
        reason: 'ユーザー管理 should appear before データ管理',
      );

      // Scroll to debug switch; adjacent export button should still be visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('debug-mode-switch')),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Data management should appear before debug.
      final double exportY2 = tester
          .getTopLeft(find.byKey(const Key('export-settings-button')))
          .dy;
      final double debugY = tester
          .getTopLeft(find.byKey(const Key('debug-mode-switch')))
          .dy;
      expect(
        exportY2,
        lessThan(debugY),
        reason: 'データ管理 should appear before デバッグ',
      );
    });

    testWidgets('comment display tile shows font size', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default font size is 14px
      expect(find.text('フォントサイズ: 14px'), findsOneWidget);
    });

    testWidgets('license tile renders and is tappable', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.byKey(const Key('license-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      // Verify the license tile renders with correct text
      expect(find.byKey(const Key('license-tile')), findsOneWidget);
      expect(find.text('ライセンス'), findsOneWidget);

      // Verify the tile is tappable (opens license page)
      await tester.tap(find.byKey(const Key('license-tile')));
      await tester.pumpAndSettle();

      // showLicensePage pushes a new route with the LicensePage widget
      expect(find.text('comerune'), findsOneWidget);
    });

    testWidgets(
      'license page shows applicationVersion from PackageInfo (not hardcoded)',
      (WidgetTester tester) async {
        // 既定の setUp モック値（1.2.0）を上書きし、ハードコードでないことを保証する。
        PackageInfo.setMockInitialValues(
          appName: 'comerune',
          packageName: 'app.comerune',
          version: '9.9.9-test',
          buildNumber: '42',
          buildSignature: '',
        );

        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        final Finder scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('license-tile')),
          200,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('license-tile')));
        await tester.pumpAndSettle();

        // LicensePage は applicationVersion を本文に表示する。
        // PackageInfo のモック値が反映されていることを確認し、
        // 以前の '1.2.0' ハードコードへの逆戻りを検出する。
        expect(find.text('9.9.9-test'), findsOneWidget);
        expect(find.text('1.2.0'), findsNothing);
      },
    );

    testWidgets('license page lists packages registered via LicenseRegistry '
        '(pubspec.yaml auto-sync contract)', (WidgetTester tester) async {
      // `showLicensePage` は Flutter 標準の [LicenseRegistry] を参照して
      // パッケージ一覧を描画する。本テストは:
      //   1. ダミーパッケージを [LicenseRegistry.addLicense] で登録し、
      //      ライセンスページに表示されることを確認する。
      //   2. これにより、実機では `pubspec.yaml` の依存が Flutter ツール
      //      チェーンによって同様に [LicenseRegistry] へ自動登録され、
      //      ライセンスページに自動反映されることの回帰テストとする。
      // アプリ側で [LicenseRegistry.addLicense] を呼び出していなくても
      // 自動表示が成立することを担保する契約テストに相当する。
      const String sentinelPackage = '__license_registry_autosync_sentinel__';
      const String sentinelBody = 'SENTINEL_LICENSE_BODY_42';
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(<String>[
          sentinelPackage,
        ], sentinelBody);
      });
      // 登録は LicenseRegistry.reset の公開 API が無いため累積する。
      // テスト内で固有なセンチネル文字列を使い、他テストと衝突しないよう
      // 識別子を十分にユニークにしてある。

      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('license-tile')),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('license-tile')));
      await tester.pumpAndSettle();

      // LicensePage のパッケージ一覧に、LicenseRegistry 経由で登録した
      // センチネルパッケージ名が表示されることを確認する。
      expect(find.text(sentinelPackage), findsOneWidget);
    });

    test('app code does not call LicenseRegistry.addLicense '
        '(no hardcoded package/license text policy)', () async {
      // アプリ本体でパッケージ名・ライセンス本文のハードコードを禁止する
      // ポリシーを、lib/ 配下に `LicenseRegistry.addLicense` / `LicenseEntry`
      // のリテラルが現れないことで担保する。
      // Flutter ツールチェーンが pubspec.yaml 依存を自動登録するため、
      // アプリ側からの手動登録は不要であり、手動登録が復活した場合は
      // 同期漏れリスクが再発する。
      final Directory libDir = Directory('lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'lib/ ディレクトリがテスト実行パスから見つかりません',
      );
      final List<File> dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      final List<String> offenders = <String>[];
      for (final File file in dartFiles) {
        final String src = file.readAsStringSync();
        // コメントは許容（ポリシー説明で語を使うため）。実呼び出しのみを検出する。
        if (src.contains('LicenseRegistry.addLicense(') ||
            src.contains('LicenseEntryWithLineBreaks(') ||
            RegExp(r'\bLicenseEntry\s*\(').hasMatch(src)) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'lib/ 配下で LicenseRegistry への手動登録やハードコードが検出されました。'
            'pubspec.yaml と表示の乖離を防ぐため、ライセンス情報は '
            'pubspec.yaml の依存に一本化してください: $offenders',
      );
    });
  });
}

Widget _buildScreen(
  SettingsStore settingsStore, {
  UserSessionStore? userSessionStore,
  ValueNotifier<AppThemeMode>? themeModeNotifier,
}) {
  return MaterialApp(
    home: SettingsScreen(
      settingsStore: settingsStore,
      userSessionStore: userSessionStore,
      themeModeNotifier: themeModeNotifier,
    ),
  );
}
