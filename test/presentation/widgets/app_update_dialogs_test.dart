import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:comerune/application/app_update/update_prompt_store.dart';
import 'package:comerune/domain/models/app_update.dart';
import 'package:comerune/domain/utils/semantic_version.dart';
import 'package:comerune/presentation/widgets/app_update_dialogs.dart';

import '../../helpers/in_memory_shared_preferences.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];
  PreferredLaunchMode? lastLaunchMode;
  bool shouldSucceed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    lastLaunchMode = options.mode;
    return shouldSucceed;
  }
}

Future<void> _present(
  WidgetTester tester, {
  required UpdateStatus status,
  required UpdatePromptStore promptStore,
  bool bypassDismissed = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return ElevatedButton(
              onPressed: () => presentUpdateStatus(
                context: context,
                status: status,
                promptStore: promptStore,
                bypassDismissed: bypassDismissed,
              ),
              child: const Text('go'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  late UrlLauncherPlatform previous;
  late _FakeUrlLauncher fakeLauncher;

  setUp(() {
    previous = UrlLauncherPlatform.instance;
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = previous;
  });

  UpdatePromptStore newStore() =>
      UpdatePromptStore(prefs: InMemorySharedPreferences());

  testWidgets('none shows nothing', (WidgetTester tester) async {
    await _present(
      tester,
      status: const UpdateStatus.none(),
      promptStore: newStore(),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('optional dialog launches release page on update', (
    WidgetTester tester,
  ) async {
    await _present(
      tester,
      status: UpdateStatus.optional(
        latestVersion: const SemanticVersion(1, 2, 0),
        releaseUrl: 'https://example.invalid/r',
      ),
      promptStore: newStore(),
    );
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-update-now')));
    await tester.pumpAndSettle();

    expect(fakeLauncher.launchedUrls, <String>['https://example.invalid/r']);
    expect(
      fakeLauncher.lastLaunchMode,
      PreferredLaunchMode.externalApplication,
    );
  });

  testWidgets(
    'optional "later" records dismissed version and suppresses next',
    (WidgetTester tester) async {
      final UpdatePromptStore store = newStore();
      final UpdateStatus status = UpdateStatus.optional(
        latestVersion: const SemanticVersion(1, 2, 0),
        releaseUrl: 'https://example.invalid/r',
      );

      await _present(tester, status: status, promptStore: store);
      await tester.tap(find.byKey(const Key('app-update-later')));
      await tester.pumpAndSettle();
      expect(store.dismissedVersion(), '1.2.0');

      // 同一版・bypass なし → 再表示しない。
      await _present(tester, status: status, promptStore: store);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('bypassDismissed shows even if previously dismissed', (
    WidgetTester tester,
  ) async {
    final UpdatePromptStore store = newStore();
    await store.setDismissedVersion('1.2.0');

    await _present(
      tester,
      status: UpdateStatus.optional(
        latestVersion: const SemanticVersion(1, 2, 0),
      ),
      promptStore: store,
      bypassDismissed: true,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('forced blocker is not dismissible by tapping outside', (
    WidgetTester tester,
  ) async {
    await _present(
      tester,
      status: UpdateStatus.forced(
        latestVersion: const SemanticVersion(2, 0, 0),
        releaseUrl: 'https://example.invalid/r',
      ),
      promptStore: newStore(),
    );
    expect(find.text('更新が必要です'), findsOneWidget);

    // バリア外（左上）をタップしても閉じない。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('更新が必要です'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-update-forced-now')));
    await tester.pumpAndSettle();
    expect(fakeLauncher.launchedUrls, <String>['https://example.invalid/r']);
  });

  testWidgets(
    'forced blocker shows inline error and stays retryable on launch failure',
    (WidgetTester tester) async {
      fakeLauncher.shouldSucceed = false;
      await _present(
        tester,
        status: UpdateStatus.forced(
          latestVersion: const SemanticVersion(2, 0, 0),
          releaseUrl: 'https://example.invalid/r',
        ),
        promptStore: newStore(),
      );

      expect(find.byKey(const Key('app-update-forced-error')), findsNothing);
      await tester.tap(find.byKey(const Key('app-update-forced-now')));
      await tester.pumpAndSettle();

      // インラインのエラーが出て、ボタンは残り再試行できる。
      expect(find.byKey(const Key('app-update-forced-error')), findsOneWidget);
      expect(find.byKey(const Key('app-update-forced-now')), findsOneWidget);
      expect(find.text('更新が必要です'), findsOneWidget);

      // 再試行で成功すればエラーは消える。
      fakeLauncher.shouldSucceed = true;
      await tester.tap(find.byKey(const Key('app-update-forced-now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-update-forced-error')), findsNothing);
      // 失敗時 + 再試行成功時の 2 回、起動が試行されている。
      expect(fakeLauncher.launchedUrls, <String>[
        'https://example.invalid/r',
        'https://example.invalid/r',
      ]);
    },
  );
}
